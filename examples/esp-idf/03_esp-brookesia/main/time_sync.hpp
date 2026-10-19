/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include <ctime>

/**
 * @brief Set up the system clock at boot: apply the time zone (the one last set via time_sync_set(), else
 *        CONFIG_EXAMPLE_TIMEZONE) and restore the time from the PCF85063 RTC (if it holds a valid time).
 *        Requires NVS to be initialized.
 *
 * Until a time is known, `time()` reports a time around 1970-01-01.
 */
void time_sync_start(void);

/**
 * @brief Set the time (e.g. from the paired phone): system clock + RTC chip, and the time zone (POSIX TZ string,
 *        persisted in NVS) unless `tz` is null or empty. Safe to call from any task.
 */
bool time_sync_set(time_t utc, const char *tz);

/**
 * @brief Set the system clock from the PCF85063 RTC (no-op if the RTC holds no valid time). Useful after light sleep,
 *        during which the ESP32's own clock runs from an imprecise RC oscillator.
 */
void time_sync_restore_from_rtc(void);
