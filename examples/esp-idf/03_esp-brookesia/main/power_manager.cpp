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
#include "ble_background.hpp"
#include "time_sync.hpp"
#include "power_manager.hpp"
#include "watch_faces.h"
#include "settings.h"

static const char *TAG = "Power";

// The power key goes to the PMU only (not readable on a GPIO, so no GPIO wakeup): poll its latched press status
static constexpr uint32_t POLL_PERIOD_MS = 250;
// After the screen goes off the touch controller stays on this long: a touch turns the screen back on
static constexpr int64_t TOUCH_WAKE_WINDOW_US = 8LL * 1000 * 1000;
static constexpr uint32_t TOUCH_POLL_PERIOD_MS = 50;   // During that window (a tap is ~100 ms)
static constexpr uint32_t TOUCH_RELEASE_WAIT_MS = 2000;

// The touch INT line went low while the screen was off (latched; the interrupt then turns itself off, since it is
// level-triggered, as light sleep's GPIO wake needs)
static volatile bool s_touch_int_seen = false;

static void touch_int_isr(void *)
{
    s_touch_int_seen = true;
    gpio_intr_disable(BSP_LCD_TOUCH_INT);
}

// The pin's interrupt is LVGL's otherwise (it reads the touch only when it fires): give it back
static void touch_int_stop()
{
    gpio_intr_disable(BSP_LCD_TOUCH_INT);
    gpio_wakeup_disable(BSP_LCD_TOUCH_INT);
    bsp_touch_restore_int();
}
static constexpr uint32_t SLEEP_IDLE_MS = 10 * 1000;    // Only on the home screen and flagged screens
static constexpr uint32_t LONG_SLEEP_IDLE_MS = 60 * 1000;   // Screens flagged POWER_MANAGER_LONG_IDLE_FLAG too
// At night, after this long asleep (on battery, BLE and music off), the PMU switches the board off; the power key
// boots it again. During the day the watch stays in light sleep (~0.75 %/h), so steps keep counting and it wakes
// instantly
static constexpr int64_t POWER_OFF_AFTER_SLEEP_US = 2LL * 60 * 60 * 1000 * 1000;
static constexpr int NIGHT_START_HOUR = 20;     // Local time; the night window wraps midnight
static constexpr int NIGHT_END_HOUR = 7;
static constexpr gpio_num_t PA_CTRL_GPIO = GPIO_NUM_6;  // Speaker amplifier enable (NS4150B), high = on

// The night clock is built on this task (night_clock_show, which also draws its date): at 6 KB, 836 bytes were left
static constexpr uint32_t TASK_STACK_SIZE = 10 * 1024;

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

// Night clock (components/watch_faces/NightClock.swift; switched on in Indstillinger): a watch lying still on its
// left side shows the time, dim (at any hour: the switch decides). Shown from sleep once it has lain like that for
// NIGHT_CLOCK_STILL_US, and straight away when the screen is woken while it lies like that (rather than the normal
// screen at full brightness first). Ends when it is picked up (no longer on its left side) or long pressed (~1 s: a
// tap doesn't); after a long press it stays away until the watch has been moved (else it would come straight back).
// The power key and the idle timeout turn the screen off as elsewhere, without ending it: woken again (key, touch),
// it's still the night clock; it just doesn't come back by itself until the watch has been moved.
static constexpr int64_t NIGHT_CLOCK_STILL_US = 3LL * 1000 * 1000;
// On its side: gravity along the screen's horizontal axis. Which IMU axis that is, and its sign with the left side
// down: NIGHT_CLOCK_AXIS (0 = x, 1 = y) and NIGHT_CLOCK_LEFT_SIGN
static constexpr int NIGHT_CLOCK_AXIS = 1;          // Measured: left side down, y = -1008 mg
static constexpr int NIGHT_CLOCK_LEFT_SIGN = -1;
static constexpr int64_t NIGHT_CLOCK_TRY_US = 20LL * 1000 * 1000;   // Tried from Indstillinger
static constexpr int32_t SIDEWAYS_MIN_MG = 800;     // Along that axis
static constexpr int32_t SIDEWAYS_MAX_OTHER_MG = 450;   // Along each of the others

static bool night_clock_shown = false;
static bool night_clock_dismissed = false;     // Long pressed away: not until moved
static bool night_clock_slept = false;         // Screen turned off from it: only at wake until moved
static int64_t night_clock_still_since = 0;
static volatile bool night_clock_tapped = false;   // Long pressed
static volatile bool night_clock_try_requested = false;
static int64_t night_clock_try_until = 0;       // While tried: shown until then, whatever the time and position

// The clock is set (else the night clock has nothing to show)
static bool clock_is_set(void)
{
    const time_t now = time(nullptr);
    struct tm t;
    localtime_r(&now, &t);
    return t.tm_year + 1900 >= 2024;
}

// Which side the watch lies on: 1 = left side down, -1 = right side down, 0 = not on its side (or no reading).
// `still`: it lay still over the last reading.
static int lying_side(bool *still, bool *have_reading)
{
    int32_t g[3];
    *still = false;
    *have_reading = step_counter_gravity(&g[0], &g[1], &g[2], still);
    if (!*have_reading) {
        return 0;
    }
    const int32_t along = g[NIGHT_CLOCK_AXIS];
    for (int a = 0; a < 3; a++) {
        if ((a != NIGHT_CLOCK_AXIS) && ((g[a] > SIDEWAYS_MAX_OTHER_MG) || (g[a] < -SIDEWAYS_MAX_OTHER_MG))) {
            return 0;
        }
    }
    if (along >= SIDEWAYS_MIN_MG) {
        return NIGHT_CLOCK_LEFT_SIGN;
    }
    if (along <= -SIDEWAYS_MIN_MG) {
        return -NIGHT_CLOCK_LEFT_SIGN;
    }
    return 0;
}

// While asleep: the side to show the night clock for, once it's due (else 0)
static int night_clock_due(void)
{
    bool still = false, have_reading = false;
    const int side = lying_side(&still, &have_reading);
    if (!have_reading) {
        return 0;
    }
    if ((side != 1) || !still) {
        night_clock_still_since = 0;
        night_clock_dismissed = false;  // Moved: it may come back next time it's laid down
        night_clock_slept = false;
        return 0;
    }
    if (night_clock_dismissed || night_clock_slept || !clock_is_set() || !settings_night_clock_enabled()) {
        return 0;
    }
    const int64_t now = esp_timer_get_time();
    if (night_clock_still_since == 0) {
        night_clock_still_since = now;
    }
    return (now - night_clock_still_since >= NIGHT_CLOCK_STILL_US) ? side : 0;
}

// Waking the screen (key, touch): straight to the night clock if it lies so (on its left side; it needn't have
// lain still for long)
static bool night_clock_at_wake(void)
{
    bool still = false, have_reading = false;
    return settings_night_clock_enabled() && !night_clock_dismissed && clock_is_set() &&
           (lying_side(&still, &have_reading) == 1);
}

static constexpr uint32_t NIGHT_CLOCK_FRAME_WAIT_MS = 500;
static volatile bool night_clock_frame_drawn = false;

static void on_night_clock_frame(lv_event_t *)
{
    night_clock_frame_drawn = true;
}

static void on_night_clock_tapped(void)
{
    night_clock_tapped = true;
}

// Back to the screen from before, at the normal brightness (with the idle countdown restarted). The LVGL lock is taken.
static void night_clock_end(bool dismissed, const char *why)
{
    bsp_display_lock(0);
    night_clock_hide();
    bsp_display_backlight_on();
    lv_display_trigger_activity(nullptr);
    bsp_display_unlock();
    night_clock_shown = false;
    night_clock_try_until = 0;
    night_clock_dismissed = dismissed;
    night_clock_still_since = 0;
    ESP_LOGI(TAG, "Night clock off: %s%s", why, dismissed ? " (until moved)" : "");
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
        const uint32_t idle_ms = lv_obj_has_flag(screen, POWER_MANAGER_LONG_IDLE_FLAG) ? LONG_SLEEP_IDLE_MS
                                 : SLEEP_IDLE_MS;
        idle = ((screen == home_screen) || lv_obj_has_flag(screen, POWER_MANAGER_IDLE_SLEEP_FLAG)) &&
               (lv_display_get_inactive_time(nullptr) >= idle_ms);
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

    // The touch controller keeps scanning for TOUCH_WAKE_WINDOW_US: a touch then turns the screen back on. It
    // reports a touch with a short low pulse on its INT line, which a poll of the line easily misses: an interrupt
    // latches it (touch_int_isr), and it also wakes light sleep. It is also asked over I2C now and then; it drops
    // into a low-power mode of its own after a few idle seconds where it doesn't answer I2C (but still pulses INT),
    // so those reads may fail: their error log is muted meanwhile. After the window it hibernates (only a reset
    // wakes it again).
    bool touch_awake = true;
    bool woken_by_touch = false;
    uint32_t touch_polls = 0;
    bool woke_on_gpio = false;  // The last light sleep (of this loop) ended by the touch INT line
    s_touch_int_seen = false;
    gpio_wakeup_enable(BSP_LCD_TOUCH_INT, GPIO_INTR_LOW_LEVEL); // also the interrupt's type
    esp_sleep_enable_gpio_wakeup();
    const esp_err_t isr_service = gpio_install_isr_service(0);
    const bool touch_isr = ((isr_service == ESP_OK) || (isr_service == ESP_ERR_INVALID_STATE)) &&
                           (gpio_isr_handler_add(BSP_LCD_TOUCH_INT, touch_int_isr, nullptr) == ESP_OK);
    if (touch_isr) {
        gpio_intr_enable(BSP_LCD_TOUCH_INT);
    } else {
        ESP_LOGW(TAG, "No touch interrupt: a quick tap may not wake");
    }
    esp_log_level_set("lcd_panel.io.i2c", ESP_LOG_NONE);

    // The power key can only be polled (its IRQ line isn't wired to the ESP32), so wake up briefly to check it
    esp_sleep_enable_timer_wakeup(TOUCH_POLL_PERIOD_MS * 1000);
    set_phase(Phase::Sleeping);
    const int64_t asleep_since = esp_timer_get_time();
    int night_side = 0;
    while (!pmu_pkey_short_pressed() && !timer_due()) {
        if (touch_awake) {
            const bool i2c_check = (++touch_polls % (POLL_PERIOD_MS / TOUCH_POLL_PERIOD_MS)) == 0;
            if (s_touch_int_seen || woke_on_gpio ||
                    (gpio_get_level(BSP_LCD_TOUCH_INT) == 0) || (i2c_check && bsp_touch_is_pressed())) {
                woken_by_touch = true;
                break;
            }
            if (esp_timer_get_time() - asleep_since >= TOUCH_WAKE_WINDOW_US) {
                touch_int_stop();
                esp_sleep_disable_wakeup_source(ESP_SLEEP_WAKEUP_GPIO);
                bsp_touch_sleep(true);  // Stop the touch controller scanning
                touch_awake = false;
                esp_sleep_enable_timer_wakeup(POLL_PERIOD_MS * 1000);
            }
        }
        battery_log_poll(true);
        step_counter_poll();    // The IMU's FIFO holds only ~4 s of samples
        night_side = night_clock_due();
        if (night_side != 0) {
            break;
        }
        const bool on_battery = !pmu_vbus_present();
        if (on_battery) {
            // Unplugged while asleep: BLE only runs in the background while charging (main.cpp); its task stops it
            // (the loop below avoids light sleep until then). Synk's BLE keeps running: it isn't background.
            ble_background_want(false);
        }
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
            vTaskDelay(pdMS_TO_TICKS(touch_awake ? TOUCH_POLL_PERIOD_MS : POLL_PERIOD_MS));
        } else {
            esp_light_sleep_start();
            woke_on_gpio = esp_sleep_get_wakeup_cause() == ESP_SLEEP_WAKEUP_GPIO;
            breadcrumb_sleep_cycles = breadcrumb_sleep_cycles + 1;
        }
    }
    esp_sleep_disable_wakeup_source(ESP_SLEEP_WAKEUP_TIMER);
    if (touch_awake) {
        touch_int_stop();
        esp_sleep_disable_wakeup_source(ESP_SLEEP_WAKEUP_GPIO);
    }
    set_phase(Phase::Waking);

    // The ESP32's clock drifts in light sleep (RC oscillator); the RTC chip's crystal doesn't
    time_sync_restore_from_rtc();

    // Woken (key, touch) lying on its left side: the night clock, before anything else is shown. Not for a
    // timer that is due: it rings over the normal screen.
    if ((night_side == 0) && !timer_due() && night_clock_at_wake()) {
        night_side = 1;
    }

    if (!touch_awake) {
        bsp_touch_sleep(false); // Reset pulse wakes the touch controller (~200 ms)
    }
    if (woken_by_touch) {
        // The waking touch mustn't also press something: give LVGL the touchscreen only after the finger lifts
        for (uint32_t waited = 0; bsp_touch_is_pressed() && (waited < TOUCH_RELEASE_WAIT_MS); waited += 20) {
            vTaskDelay(pdMS_TO_TICKS(20));
        }
    }
    esp_log_level_set("lcd_panel.io.i2c", ESP_LOG_WARN);
    lvgl_port_resume();
    bsp_display_lock(0);
    bsp_display_sleep(false);   // ~120 ms
    if (touch != nullptr) {
        lv_indev_enable(touch, true);
    }
    lv_display_trigger_activity(nullptr);   // Restart the idle countdown
    if ((night_side == 0) && night_clock_shown) {
        // Asleep from the night clock, woken not lying so (or for a timer): back to the screen from before
        night_clock_hide();
        night_clock_shown = false;
    }
    if (night_side != 0) {
        night_clock_tapped = false;
        night_clock_show(night_side);   // (Still there if it was asleep from it)
        lv_obj_invalidate(lv_screen_active());
        night_clock_frame_drawn = false;
        lv_display_add_event_cb(lv_display_get_default(), on_night_clock_frame, LV_EVENT_REFR_READY, nullptr);
    } else {
        lv_obj_invalidate(lv_screen_active());
        bsp_display_backlight_on();
    }
    bsp_display_unlock();
    if (night_side != 0) {
        // The screen lights up once the LVGL task has drawn the clock (it still holds the frame from before). Not
        // drawn here: rendering needs far more stack than this task has.
        for (uint32_t waited = 0; !night_clock_frame_drawn && (waited < NIGHT_CLOCK_FRAME_WAIT_MS); waited += 10) {
            vTaskDelay(pdMS_TO_TICKS(10));
        }
        bsp_display_lock(0);
        lv_display_remove_event_cb_with_user_data(lv_display_get_default(), on_night_clock_frame, nullptr);
        bsp_display_brightness_set(settings_night_brightness());
        bsp_display_unlock();
        night_clock_shown = true;
    }

    set_phase(Phase::Awake);
    ESP_LOGI(TAG, "Wake%s (%" PRIu32 " sleep cycles so far, power task stack free: %u bytes)",
             (night_side != 0) ? ": night clock" : (woken_by_touch ? " by touch" : ""), breadcrumb_sleep_cycles,
             (unsigned)uxTaskGetStackHighWaterMark(nullptr));
}

static void power_task(void *arg)
{
    while (true) {
        // On USB power too, the screen goes off after a while idle; the sleep loop then keeps the CPU awake (no light
        // sleep), so the USB console and flashing keep working
        if (night_clock_try_requested && !night_clock_shown) {
            night_clock_try_requested = false;
            bool still = false, have_reading = false;
            const int side = lying_side(&still, &have_reading);
            if (bsp_display_lock(0)) {
                night_clock_tapped = false;
                night_clock_show((side != 0) ? side : 1);   // As if on its left side, unless it lies on one
                bsp_display_brightness_set(settings_night_brightness());
                bsp_display_unlock();
                night_clock_shown = true;
                night_clock_try_until = esp_timer_get_time() + NIGHT_CLOCK_TRY_US;
            }
        }
        if (night_clock_shown) {
            // Stays on (it isn't an idle screen) until long pressed, the key or picked up
            bool still = false, have_reading = false;
            const int side = lying_side(&still, &have_reading);
            bool idle = false;
            if (bsp_display_lock(0)) {
                idle = lv_display_get_inactive_time(nullptr) >= SLEEP_IDLE_MS;
                bsp_display_unlock();
            }
            const bool key = pmu_pkey_short_pressed();     // (Reading it clears it)
            if (key && (night_clock_try_until != 0)) {
                night_clock_end(false, "key");
                sleep_until_power_key();
            } else if ((key || idle) && (night_clock_try_until == 0)) {
                // Screen off, still the night clock (shown again at wake if it lies so)
                night_clock_slept = true;
                sleep_until_power_key();
            } else if (night_clock_tapped) {
                night_clock_end(night_clock_try_until == 0, "long press");
            } else if (night_clock_try_until != 0) {
                if (esp_timer_get_time() >= night_clock_try_until) {
                    night_clock_end(false, "try over");
                }
            } else if ((have_reading && (side != 1)) || !clock_is_set() || !settings_night_clock_enabled()) {
                night_clock_end(false, "not on its left side");
            }
        } else if (pmu_pkey_short_pressed()) {
            bool handled = false;
            if ((key_callback != nullptr) && bsp_display_lock(0)) {
                handled = key_callback();
                lv_display_trigger_activity(nullptr);   // Restart the idle countdown on the new screen
                bsp_display_unlock();
            }
            if (!handled) {
                sleep_until_power_key();
            }
        } else if (home_screen_idle()) {
            sleep_until_power_key();
        }
        battery_log_poll(false);
        vTaskDelay(pdMS_TO_TICKS(POLL_PERIOD_MS));
    }
}

void power_manager_try_night_clock(void)
{
    night_clock_try_requested = true;
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
    night_clock_set_tap_handler(on_night_clock_tapped);
    xTaskCreate(power_task, "power", TASK_STACK_SIZE, nullptr, 3, nullptr);
}
