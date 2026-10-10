/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

/**
 * @brief Set up the system clock:
 *        1. Apply the configured time zone
 *        2. Restore the time from the PCF85063 RTC (if it holds a valid time)
 *        3. In the background: connect to the configured Wi-Fi, sync once via SNTP, store the result in the RTC and
 *           shut Wi-Fi down again
 *
 * Until a time is known, `time()` reports a time around 1970-01-01.
 */
void time_sync_start(void);
