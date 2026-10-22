/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include <atomic>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "ble_sync.h"
#include "ble_background.hpp"

static std::atomic<bool> wanted{false};

static void ble_background_task(void *arg)
{
    bool applied = false;
    int since_retry = 0;
    while (true) {
        const bool want = wanted.load();
        // Also retried (every 5 s) while wanted but not running, e.g. when it couldn't start, or the watch got paired
        if ((want != applied) || (want && !ble_sync_is_active() && ++since_retry >= 25)) {
            ble_sync_set_background(want);
            applied = want;
            since_retry = 0;
        }
        vTaskDelay(pdMS_TO_TICKS(200));
    }
}

void ble_background_start(void)
{
    // Priority 2: below the UI. 4 KB: NimBLE init/deinit run here
    xTaskCreate(ble_background_task, "ble_bg", 4096, nullptr, 2, nullptr);
}

void ble_background_want(bool want)
{
    wanted.store(want);
}
