/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

/**
 * @brief AXP2101 power management chip on the board's I2C bus: power button, USB power, battery and power-off.
 *        The button and USB are wired to the PMU (its IRQ pin isn't connected to the ESP32), so they're polled.
 */

/**
 * @brief Set up the PMU: enable the power key's short-press IRQ status, the fuel gauge and battery voltage ADC, and
 *        make a ~4 s press of the power key switch the board off
 */
bool pmu_init(void);

/**
 * @brief Make sure every power rail the board uses is on (call first thing at boot). The PMU keeps its settings while
 *        the battery is connected, even across power-off, so a rail switched off once would otherwise stay off.
 */
bool pmu_ensure_rails(void);

/**
 * @brief Whether the power button was short-pressed since the last call (clears the latched status)
 */
bool pmu_pkey_short_pressed(void);

/**
 * @brief Whether USB (VBUS) power is connected
 */
bool pmu_vbus_present(void);

struct PmuBattery {
    bool present;       // A battery is connected
    bool charging;
    int percent;        // Fuel gauge, 0..100 (-1 if unknown)
    int millivolts;
};

bool pmu_battery(PmuBattery *battery);

/**
 * @brief Switch the whole board off (all rails except the RTC's). Pressing the power button boots it again.
 */
void pmu_power_off(void);

