#pragma once

#include <stdint.h>
#include "lvgl.h"

#ifdef __cplusplus
extern "C" {
#endif

/* The Stopur (stopwatch) and Timer apps, in Embedded Swift. Their state lives on when the apps close: a stopwatch
 * keeps running, and a timer keeps counting down, wakes the watch when it's done, opens the Timer app and rings. */

/* Once at boot, after the file store is mounted and LVGL runs (with the LVGL lock held). `open_timer_app` starts the
 * Timer app when a timer is done while another app (or none) is shown; called with the LVGL lock held. */
void watch_tools_init(void (*open_timer_app)(void));

/* When the watch must be awake for a running timer (esp_timer_get_time() microseconds), 0 = no timer. Thread-safe:
 * for the power manager's sleep loop. */
int64_t watch_tools_wake_at_us(void);

/* The apps' run()/close(), with the LVGL lock held; `screen` is the app's (default) screen. */
void stopwatch_app_show(lv_obj_t *screen);
void stopwatch_app_hide(void);
void timer_app_show(lv_obj_t *screen);
void timer_app_hide(void);

#ifdef __cplusplus
}
#endif
