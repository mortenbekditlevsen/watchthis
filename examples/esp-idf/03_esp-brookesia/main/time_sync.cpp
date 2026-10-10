/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include <cinttypes>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <sys/time.h>
#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_netif_sntp.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs_flash.h"
#include "sdkconfig.h"
#include "rtc_pcf85063.hpp"
#include "time_sync.hpp"

static const char *TAG = "TimeSync";

static constexpr uint32_t SNTP_SYNC_TIMEOUT_MS = 60 * 1000;

static esp_netif_t *sta_netif = nullptr;
static esp_event_handler_instance_t wifi_event_instance = nullptr;
static esp_event_handler_instance_t ip_event_instance = nullptr;

static void log_time(const char *what, time_t utc)
{
    struct tm timeinfo;
    char buf[32];

    localtime_r(&utc, &timeinfo);
    strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", &timeinfo);
    ESP_LOGI(TAG, "%s: %s", what, buf);
}

static void restore_time_from_rtc(void)
{
    time_t utc;

    if (!rtc_pcf85063_read(&utc)) {
        ESP_LOGW(TAG, "No valid time in RTC");
        return;
    }

    struct timeval tv = {.tv_sec = utc, .tv_usec = 0};
    settimeofday(&tv, nullptr);
    log_time("Time restored from RTC", utc);
}

static void on_wifi_event(void *arg, esp_event_base_t event_base, int32_t event_id, void *event_data)
{
    if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
    } else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_DISCONNECTED) {
        auto *event = static_cast<wifi_event_sta_disconnected_t *>(event_data);
        ESP_LOGW(TAG, "Disconnected (reason %d), reconnecting", event->reason);
        esp_wifi_connect();
    } else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
        auto *event = static_cast<ip_event_got_ip_t *>(event_data);
        ESP_LOGI(TAG, "Got IP " IPSTR, IP2STR(&event->ip_info.ip));
    }
}

static esp_err_t wifi_start(void)
{
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    sta_netif = esp_netif_create_default_wifi_sta();

    wifi_init_config_t init_cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&init_cfg));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(
                        WIFI_EVENT, ESP_EVENT_ANY_ID, on_wifi_event, nullptr, &wifi_event_instance
                    ));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(
                        IP_EVENT, IP_EVENT_STA_GOT_IP, on_wifi_event, nullptr, &ip_event_instance
                    ));

    wifi_config_t wifi_cfg = {};
    strlcpy(reinterpret_cast<char *>(wifi_cfg.sta.ssid), CONFIG_EXAMPLE_WIFI_SSID, sizeof(wifi_cfg.sta.ssid));
    strlcpy(reinterpret_cast<char *>(wifi_cfg.sta.password), CONFIG_EXAMPLE_WIFI_PASSWORD, sizeof(wifi_cfg.sta.password));
    wifi_cfg.sta.threshold.authmode = (strlen(CONFIG_EXAMPLE_WIFI_PASSWORD) == 0) ? WIFI_AUTH_OPEN : WIFI_AUTH_WPA2_PSK;
    wifi_cfg.sta.sae_pwe_h2e = WPA3_SAE_PWE_BOTH;

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wifi_cfg));
    ESP_ERROR_CHECK(esp_wifi_start());
    ESP_LOGI(TAG, "Connecting to \"%s\"", CONFIG_EXAMPLE_WIFI_SSID);

    return ESP_OK;
}

static void wifi_stop(void)
{
    // Unregister first, otherwise the disconnect event below would trigger a reconnect
    esp_event_handler_instance_unregister(WIFI_EVENT, ESP_EVENT_ANY_ID, wifi_event_instance);
    esp_event_handler_instance_unregister(IP_EVENT, IP_EVENT_STA_GOT_IP, ip_event_instance);
    esp_wifi_disconnect();
    esp_wifi_stop();
    // Release the Wi-Fi driver's memory as well; the C6 has no PSRAM
    esp_wifi_deinit();
    esp_netif_destroy_default_wifi(sta_netif);
    sta_netif = nullptr;
    ESP_LOGI(TAG, "Wi-Fi off");
}

static void sync_task(void *arg)
{
    ESP_ERROR_CHECK(wifi_start());

    esp_sntp_config_t sntp_cfg = ESP_NETIF_SNTP_DEFAULT_CONFIG(CONFIG_EXAMPLE_SNTP_SERVER);
    ESP_ERROR_CHECK(esp_netif_sntp_init(&sntp_cfg));

    if (esp_netif_sntp_sync_wait(pdMS_TO_TICKS(SNTP_SYNC_TIMEOUT_MS)) == ESP_OK) {
        time_t now = time(nullptr);
        log_time("Time synced", now);
        if (!rtc_pcf85063_write(now)) {
            ESP_LOGE(TAG, "Storing time in RTC failed");
        }
    } else {
        ESP_LOGW(TAG, "Time sync timed out after %" PRIu32 " s", SNTP_SYNC_TIMEOUT_MS / 1000);
    }

    esp_netif_sntp_deinit();
    wifi_stop();

    vTaskDelete(nullptr);
}

void time_sync_start(void)
{
    setenv("TZ", CONFIG_EXAMPLE_TIMEZONE, 1);
    tzset();

    restore_time_from_rtc();

    if (strlen(CONFIG_EXAMPLE_WIFI_SSID) == 0) {
        ESP_LOGW(TAG, "No Wi-Fi SSID configured (idf.py menuconfig -> Example: Wi-Fi time sync), skipping time sync");
        return;
    }

    xTaskCreate(sync_task, "time_sync", 4096, nullptr, 3, nullptr);
}
