/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include <cstdio>
#include <ctime>
#include <sys/stat.h>
#include "esp_log.h"
#include "esp_timer.h"
#include "file_store.h"
#include "pmu.hpp"
#include "battery_log.hpp"

static const char *TAG = "BatteryLog";

static constexpr int64_t LOG_INTERVAL_US = 15LL * 60 * 1000 * 1000;
static constexpr off_t ROTATE_SIZE = 32 * 1024;
static constexpr const char *LOG_PATH = FILE_STORE_ROOT "/battery.csv";
static constexpr const char *OLD_PATH = FILE_STORE_ROOT "/battery.old.csv";

// esp_timer keeps counting through light sleep, so it measures real elapsed time
static int64_t last_log_us = -LOG_INTERVAL_US;

void battery_log_now(bool asleep, const char *note)
{
    last_log_us = esp_timer_get_time();

    PmuBattery battery;
    if (!pmu_battery(&battery)) {
        return;
    }
    char when[24];
    time_t now = time(nullptr);
    struct tm t;
    localtime_r(&now, &t);
    strftime(when, sizeof(when), "%Y-%m-%d %H:%M", &t);

    char line[96];
    snprintf(line, sizeof(line), "%s,%d,%d,%d,%d%s%s", when, battery.percent, battery.millivolts, battery.charging,
             asleep, (note != nullptr) ? "," : "", (note != nullptr) ? note : "");
    ESP_LOGI(TAG, "%s", line);

    struct stat st;
    if ((stat(LOG_PATH, &st) == 0) && (st.st_size > ROTATE_SIZE)) {
        remove(OLD_PATH);
        rename(LOG_PATH, OLD_PATH);
    }
    FILE *f = fopen(LOG_PATH, "a");
    if (f != nullptr) {
        fprintf(f, "%s\n", line);
        fclose(f);
    }
}

void battery_log_poll(bool asleep)
{
    if (esp_timer_get_time() - last_log_us >= LOG_INTERVAL_US) {
        battery_log_now(asleep, nullptr);
    }
}
