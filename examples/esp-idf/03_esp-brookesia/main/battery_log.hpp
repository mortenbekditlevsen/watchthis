/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

/**
 * @brief Battery log for measuring drain: every 15 minutes (awake or asleep) appends
 *        `local time,percent,mV,charging,asleep` to /store/battery.csv (rotated to battery.old.csv at 32 KB) and prints
 *        it to the console. Call often; it only logs when an entry is due. Not thread-safe: call from one task.
 */
void battery_log_poll(bool asleep);

/**
 * @brief Log an entry now, with a note (e.g. "poweroff"), regardless of the interval
 */
void battery_log_now(bool asleep, const char *note);
