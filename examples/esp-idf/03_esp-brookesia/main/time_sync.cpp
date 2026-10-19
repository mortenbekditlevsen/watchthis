/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <sys/time.h>
#include "esp_log.h"
#include "nvs.h"
#include "sdkconfig.h"
#include "rtc_pcf85063.hpp"
#include "time_sync.hpp"

static const char *TAG = "TimeSync";

static constexpr const char *NVS_NAMESPACE = "time";
static constexpr const char *NVS_KEY_TZ = "tz";
static constexpr size_t TZ_MAX_LEN = 64;    // Including the terminating NUL

static void log_time(const char *what, time_t utc)
{
    struct tm timeinfo;
    char buf[32];

    localtime_r(&utc, &timeinfo);
    strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", &timeinfo);
    ESP_LOGI(TAG, "%s: %s", what, buf);
}

static void apply_timezone(const char *tz)
{
    setenv("TZ", tz, 1);
    tzset();
}

void time_sync_restore_from_rtc(void)
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

bool time_sync_set(time_t utc, const char *tz)
{
    if ((tz != nullptr) && (tz[0] != '\0')) {
        if (strlen(tz) >= TZ_MAX_LEN) {
            ESP_LOGE(TAG, "Time zone too long");
            return false;
        }
        apply_timezone(tz);
        nvs_handle_t nvs;
        if (nvs_open(NVS_NAMESPACE, NVS_READWRITE, &nvs) == ESP_OK) {
            nvs_set_str(nvs, NVS_KEY_TZ, tz);
            nvs_commit(nvs);
            nvs_close(nvs);
        }
    }

    struct timeval tv = {.tv_sec = utc, .tv_usec = 0};
    settimeofday(&tv, nullptr);
    if (!rtc_pcf85063_write(utc)) {
        ESP_LOGE(TAG, "Storing time in RTC failed");
    }
    log_time("Time set", utc);

    return true;
}

void time_sync_start(void)
{
    // The time zone the phone set last, else the build-time default
    char tz[TZ_MAX_LEN] = CONFIG_EXAMPLE_TIMEZONE;
    nvs_handle_t nvs;
    if (nvs_open(NVS_NAMESPACE, NVS_READONLY, &nvs) == ESP_OK) {
        size_t len = sizeof(tz);
        if (nvs_get_str(nvs, NVS_KEY_TZ, tz, &len) != ESP_OK) {
            strlcpy(tz, CONFIG_EXAMPLE_TIMEZONE, sizeof(tz));
        }
        nvs_close(nvs);
    }
    apply_timezone(tz);

    time_sync_restore_from_rtc();
}
