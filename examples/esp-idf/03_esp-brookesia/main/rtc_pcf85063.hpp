/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include <ctime>

/**
 * @brief Minimal driver for the PCF85063 real-time clock on the board's I2C bus. The RTC runs from its own
 *        32.768 kHz crystal, so it keeps accurate time while the ESP32-C6 sleeps or is reset. Time is stored as UTC.
 */

/**
 * @brief Read the time from the RTC
 *
 * @return true if the RTC holds a valid time (its oscillator has not stopped since the time was last written)
 */
bool rtc_pcf85063_read(time_t *utc);

/**
 * @brief Write the time to the RTC (also clears the oscillator-stopped flag)
 */
bool rtc_pcf85063_write(time_t utc);
