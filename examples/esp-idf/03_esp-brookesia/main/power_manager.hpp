/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include "lvgl.h"

/**
 * Screens with this LVGL flag also fall asleep when idle (besides the home screen). Set by apps on their own
 * screens, e.g. the watch face in "Ur"; apps outside `main` use LV_OBJ_FLAG_USER_1 directly.
 */
#define POWER_MANAGER_IDLE_SLEEP_FLAG LV_OBJ_FLAG_USER_1

/**
 * Called on a short press of the power button while awake, with the LVGL lock held. Returns true if it handled the
 * press (e.g. navigated back), false to put the watch to sleep.
 */
typedef bool (*power_manager_key_cb_t)(void);

/**
 * @brief Put the watch to sleep (display off, LVGL paused, CPU in light sleep) on a short press of the power button
 *        that `key_cb` doesn't handle, or after a while without touches while `home_screen` (or a screen flagged
 *        with POWER_MANAGER_IDLE_SLEEP_FLAG) is showing. Another press wakes it.
 *
 * Call after the GUI is up and pmu_init() has succeeded.
 */
void power_manager_start(lv_obj_t *home_screen, power_manager_key_cb_t key_cb);
