/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include <cstring>
#include <mutex>
#include "bsp/esp-bsp.h"
#include "esp_log.h"
#include "nvs.h"
#include "watch_name.hpp"

static const char *TAG = "WatchName";

static constexpr const char *NVS_NAMESPACE = "watch";
static constexpr const char *NVS_KEY = "name";
static constexpr uint32_t LOCK_TIMEOUT_MS = 1000;

static std::mutex lock;
static char name[WATCH_NAME_MAX_LEN + 1] = "";
static lv_obj_t *label = nullptr;

static bool valid(const char *text)
{
    const size_t len = strlen(text);
    if ((len == 0) || (len > WATCH_NAME_MAX_LEN)) {
        return false;
    }
    for (size_t i = 0; i < len; i++) {
        if ((uint8_t)text[i] < 0x20) {
            return false;
        }
    }
    return true;
}

static bool store(const char *text)
{
    nvs_handle_t nvs;
    if (nvs_open(NVS_NAMESPACE, NVS_READWRITE, &nvs) != ESP_OK) {
        return false;
    }
    const bool ok = (nvs_set_str(nvs, NVS_KEY, text) == ESP_OK) && (nvs_commit(nvs) == ESP_OK);
    nvs_close(nvs);
    return ok;
}

void watch_name_init(const char *initial_name)
{
    std::lock_guard<std::mutex> guard(lock);

    nvs_handle_t nvs;
    size_t len = sizeof(name);
    if ((nvs_open(NVS_NAMESPACE, NVS_READONLY, &nvs) == ESP_OK)) {
        const esp_err_t err = nvs_get_str(nvs, NVS_KEY, name, &len);
        nvs_close(nvs);
        if ((err == ESP_OK) && valid(name)) {
            ESP_LOGI(TAG, "Name: %s", name);
            return;
        }
    }
    strlcpy(name, initial_name, sizeof(name));
    store(name);
    ESP_LOGI(TAG, "Name: %s (initial)", name);
}

const char *watch_name_get(void)
{
    return name;
}

void watch_name_attach_label(lv_obj_t *new_label)
{
    std::lock_guard<std::mutex> guard(lock);
    label = new_label;
    lv_label_set_text(label, name);
}

bool watch_name_set(const char *new_name)
{
    if ((new_name == nullptr) || !valid(new_name)) {
        return false;
    }
    std::lock_guard<std::mutex> guard(lock);
    if (strcmp(name, new_name) != 0) {
        if (!store(new_name)) {
            ESP_LOGE(TAG, "Saving the name failed");
            return false;
        }
        strlcpy(name, new_name, sizeof(name));
        ESP_LOGI(TAG, "Name set: %s", name);
    }
    if ((label != nullptr) && bsp_display_lock(LOCK_TIMEOUT_MS)) {
        lv_label_set_text(label, name);
        bsp_display_unlock();
    }
    return true;
}
