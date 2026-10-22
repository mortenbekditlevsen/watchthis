/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include <cinttypes>
#include <ctime>
#include "bsp/esp-bsp.h"
#include "bsp/touch.h"
#include "driver/gpio.h"
#include "esp_attr.h"
#include "esp_log.h"
#include "esp_lvgl_port.h"
#include "esp_sleep.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_timer.h"
#include "pmu.hpp"
#include "battery_log.hpp"
#include "ble_sync.h"
#include "step_counter.h"
#include "music_player.h"
#include "watch_tools.h"
#include "time_sync.hpp"
#include "power_manager.hpp"

static const char *TAG = "Power";

// The power key goes to the PMU only (not readable on a GPIO, so no GPIO wakeup): poll its latched press status
static constexpr uint32_t POLL_PERIOD_MS = 250;
static constexpr uint32_t SLEEP_IDLE_MS = 10 * 1000;    // Only on the home screen and flagged screens
// At night, after this long asleep (on battery, BLE and music off), the PMU switches the board off; the power key
// boots it again. During the day the watch stays in light sleep (~0.75 %/h), so steps keep counting and it wakes
// instantly
static constexpr int64_t POWER_OFF_AFTER_SLEEP_US = 2LL * 60 * 60 * 1000 * 1000;
static constexpr int NIGHT_START_HOUR = 20;     // Local time; the night window wraps midnight
static constexpr int NIGHT_END_HOUR = 7;
static constexpr gpio_num_t PA_CTRL_GPIO = GPIO_NUM_6;  // Speaker amplifier enable (NS4150B), high = on

static constexpr uint32_t TASK_STACK_SIZE = 6 * 1024;

static lv_obj_t *home_screen = nullptr;
static power_manager_key_cb_t key_callback = nullptr;

// Diagnostics for unexpected reboots: kept in RTC memory, which survives software/watchdog/panic resets (not power
// loss), and reported at the next boot together with the reset reason
enum class Phase : uint32_t { Awake, EnteringSleep, Sleeping, Waking };
static constexpr uint32_t BREADCRUMB_MAGIC = 0x5EE9C0DE;
static RTC_NOINIT_ATTR uint32_t breadcrumb_magic;
static RTC_NOINIT_ATTR Phase breadcrumb_phase;
static RTC_NOINIT_ATTR uint32_t breadcrumb_sleep_cycles;

static void set_phase(Phase phase)
{
    breadcrumb_phase = phase;
}

static const char *reset_reason_name(esp_reset_reason_t reason)
{
    switch (reason) {
    case ESP_RST_POWERON: return "power-on";
    case ESP_RST_EXT: return "external pin";
    case ESP_RST_SW: return "software (esp_restart)";
    case ESP_RST_PANIC: return "panic/exception";
    case ESP_RST_INT_WDT: return "interrupt watchdog";
    case ESP_RST_TASK_WDT: return "task watchdog";
    case ESP_RST_WDT: return "other watchdog";
    case ESP_RST_DEEPSLEEP: return "deep sleep";
    case ESP_RST_BROWNOUT: return "brownout";
    case ESP_RST_SDIO: return "SDIO";
    case ESP_RST_USB: return "USB peripheral";
    case ESP_RST_JTAG: return "JTAG";
    case ESP_RST_EFUSE: return "efuse error";
    case ESP_RST_PWR_GLITCH: return "power glitch";
    case ESP_RST_CPU_LOCKUP: return "CPU lockup";
    default: return "unknown";
    }
}

static const char *phase_name(Phase phase)
{
    switch (phase) {
    case Phase::Awake: return "awake";
    case Phase::EnteringSleep: return "entering sleep";
    case Phase::Sleeping: return "sleeping";
    case Phase::Waking: return "waking";
    default: return "?";
    }
}

static void report_last_reset(void)
{
    esp_reset_reason_t reason = esp_reset_reason();

    if (breadcrumb_magic == BREADCRUMB_MAGIC) {
        ESP_LOGW(TAG, "Last reset: %s (%d); power manager was %s, after %" PRIu32 " sleep cycles",
                 reset_reason_name(reason), reason, phase_name(breadcrumb_phase), breadcrumb_sleep_cycles);
    } else {
        ESP_LOGI(TAG, "Last reset: %s (%d)", reset_reason_name(reason), reason);
    }

    breadcrumb_magic = BREADCRUMB_MAGIC;
    breadcrumb_phase = Phase::Awake;
    breadcrumb_sleep_cycles = 0;
}

// True between NIGHT_START_HOUR and NIGHT_END_HOUR local time, and if the clock isn't set (better off than drained)
static bool is_night(void)
{
    const time_t now = time(nullptr);
    struct tm t;
    localtime_r(&now, &t);
    if (t.tm_year + 1900 < 2024) {
        return true;
    }
    return (t.tm_hour >= NIGHT_START_HOUR) || (t.tm_hour < NIGHT_END_HOUR);
}

// A running timer (Timer app) is due: wake up so it can ring
static bool timer_due(void)
{
    const int64_t wake_at = watch_tools_wake_at_us();
    return (wake_at > 0) && (esp_timer_get_time() >= wake_at);
}

static bool home_screen_idle(void)
{
    bool idle = false;

    if (bsp_display_lock(0)) {
        lv_obj_t *screen = lv_screen_active();
        idle = ((screen == home_screen) || lv_obj_has_flag(screen, POWER_MANAGER_IDLE_SLEEP_FLAG)) &&
               (lv_display_get_inactive_time(nullptr) >= SLEEP_IDLE_MS);
        bsp_display_unlock();
    }

    return idle;
}

static void sleep_until_power_key(void)
{
    ESP_LOGI(TAG, "Sleep");
    set_phase(Phase::EnteringSleep);

    // Take the lock so the brightness command can't interleave with an LVGL flush. Then stop LVGL's timers (nothing
    // redraws) and disable touch input: lvgl_port_stop() alone still lets the LVGL task read touches, which would
    // both click the hidden UI and start I2C transfers that light sleep could cut off mid-way
    lv_indev_t *touch = bsp_display_get_input_dev();
    bsp_display_lock(0);
    bsp_display_brightness_set(0);
    bsp_display_sleep(true);    // The AMOLED controller's own sleep mode: far less than just brightness 0
    if (touch != nullptr) {
        lv_indev_enable(touch, false);
    }
    bsp_display_unlock();
    lvgl_port_stop();
    bsp_touch_sleep(true);      // Stop the touch controller scanning

    // The power key can only be polled (its IRQ line isn't wired to the ESP32), so wake up briefly to check it
    esp_sleep_enable_timer_wakeup(POLL_PERIOD_MS * 1000);
    set_phase(Phase::Sleeping);
    const int64_t asleep_since = esp_timer_get_time();
    while (!pmu_pkey_short_pressed() && !timer_due()) {
        battery_log_poll(true);
        step_counter_poll();    // The IMU's FIFO holds only ~4 s of samples
        const bool on_battery = !pmu_vbus_present();
        if (on_battery && !ble_sync_is_active() && !music_player_is_active() &&
                (esp_timer_get_time() - asleep_since >= POWER_OFF_AFTER_SLEEP_US) && is_night()) {
            // Asleep for hours at night: switch the board off; the RTC chip keeps the time, the power key boots it
            step_counter_save();
            battery_log_now(true, "poweroff");
            pmu_power_off();
            vTaskDelay(portMAX_DELAY);
        }
        if (ble_sync_is_active() || music_player_is_playing() || music_player_alarm_active() || !on_battery) {
            // Screen off only: light sleep would cut off the BLE link (Synk app), the music or the USB connection
            vTaskDelay(pdMS_TO_TICKS(POLL_PERIOD_MS));
        } else {
            esp_light_sleep_start();
            breadcrumb_sleep_cycles = breadcrumb_sleep_cycles + 1;
        }
    }
    esp_sleep_disable_wakeup_source(ESP_SLEEP_WAKEUP_TIMER);
    set_phase(Phase::Waking);

    // The ESP32's clock drifts in light sleep (RC oscillator); the RTC chip's crystal doesn't
    time_sync_restore_from_rtc();

    bsp_touch_sleep(false);     // Reset pulse wakes the touch controller (~200 ms)
    lvgl_port_resume();
    bsp_display_lock(0);
    bsp_display_sleep(false);   // ~120 ms
    if (touch != nullptr) {
        lv_indev_enable(touch, true);
    }
    lv_display_trigger_activity(nullptr);   // Restart the idle countdown
    lv_obj_invalidate(lv_screen_active());
    bsp_display_backlight_on();
    bsp_display_unlock();

    set_phase(Phase::Awake);
    ESP_LOGI(TAG, "Wake (%" PRIu32 " sleep cycles so far, power task stack free: %u bytes)", breadcrumb_sleep_cycles,
             (unsigned)uxTaskGetStackHighWaterMark(nullptr));
}

static void power_task(void *arg)
{
    while (true) {
        // On USB power the watch never falls asleep by itself (keeps the USB console and flashing usable)
        if (pmu_pkey_short_pressed()) {
            bool handled = false;
            if ((key_callback != nullptr) && bsp_display_lock(0)) {
                handled = key_callback();
                lv_display_trigger_activity(nullptr);   // Restart the idle countdown on the new screen
                bsp_display_unlock();
            }
            if (!handled) {
                sleep_until_power_key();
            }
        } else if (!pmu_vbus_present() && home_screen_idle()) {
            sleep_until_power_key();
        }
        battery_log_poll(false);
        vTaskDelay(pdMS_TO_TICKS(POLL_PERIOD_MS));
    }
}

void power_manager_start(lv_obj_t *screen, power_manager_key_cb_t key_cb)
{
    report_last_reset();

    // Speaker amplifier off until something plays audio
    gpio_config_t pa_cfg = {};
    pa_cfg.pin_bit_mask = 1ULL << PA_CTRL_GPIO;
    pa_cfg.mode = GPIO_MODE_OUTPUT;
    gpio_config(&pa_cfg);
    gpio_set_level(PA_CTRL_GPIO, 0);

    home_screen = screen;
    key_callback = key_cb;
    xTaskCreate(power_task, "power", TASK_STACK_SIZE, nullptr, 3, nullptr);
}
