/*
 * SPDX-FileCopyrightText: 2023-2025 Espressif Systems (Shanghai) CO LTD
 *
 * SPDX-License-Identifier: CC0-1.0
 */

#include "bsp/esp-bsp.h"
#include "esp_brookesia.hpp"
#include "boost/thread.hpp"
#ifdef ESP_UTILS_LOG_TAG
#   undef ESP_UTILS_LOG_TAG
#endif
#define ESP_UTILS_LOG_TAG "Main"
#include "esp_lib_utils.h"
#include "./dark/stylesheet.hpp"
#include "time_sync.hpp"
#include "pmu.hpp"
#include "audio_power.hpp"
#include "power_manager.hpp"
#include "file_store.h"
#include "nvs_flash.h"
#include "ble_sync.h"
#include "step_counter.h"
#include "music_player.h"
#include "watch_fonts.h"
#include "watch_name.hpp"
#include "watch_faces.h"
#include "watch_tools.h"
#include "ble_background.hpp"
#include "src/display/lv_display_private.h"

using namespace esp_brookesia;
using namespace esp_brookesia::gui;
using namespace esp_brookesia::systems::phone;

#define LVGL_PORT_INIT_CONFIG() \
    {                               \
        .task_priority = 4,       \
        .task_stack = 12 * 1024,  /* + LVGL's TJPGD decoder needs 4 KB of stack on top */ \
        .task_affinity = -1,      \
        .task_max_sleep_ms = 500, \
        .timer_period_ms = 5,     \
    }

constexpr bool EXAMPLE_SHOW_MEM_INFO = false;

constexpr uint32_t BATTERY_UPDATE_S = 30;
constexpr uint32_t STEPS_SAVE_S = 60 * 60;

// App opened at power-on (by its registry name); the launcher is one swipe up away
constexpr const char *BOOT_APP_NAME = "Ur";

// Launcher order (registry names, i.e. the app titles), 4 per page; apps not listed follow in registration order
static const char *const APP_ORDER[] = {"Ur", "Skridt", "Stopur", "Tidstagning", "Vejr", "Katte", "Musik", "Partikler", "Det lille spil", "Basket", "Synk"};

// The watch's name is the home screen title, shown in the band between the status bar and the app launcher (see
// dark/app_launcher_data.hpp). It's stored on the watch (watch_name.cpp); this is only the initial name of a watch
// without one, overridable at build time with the HOME_TITLE environment variable (see CMakeLists.txt)
#ifndef HOME_TITLE_TEXT
#define HOME_TITLE_TEXT "Bertha"
#endif
constexpr const char *INITIAL_WATCH_NAME = HOME_TITLE_TEXT;
constexpr int32_t HOME_TITLE_Y = 58;
constexpr int32_t HOME_TITLE_WIDTH = 380;

static Phone *phone_instance = nullptr;
static int watch_app_id = -1;   // The boot app ("Ur"), -1 = not installed

static bool send_app_event(int id, systems::base::Context::AppEventType type)
{
    systems::base::Context::AppEventData event = {
        .id = id,
        .type = type,
        .data = nullptr,
    };
    return phone_instance->sendAppEvent(&event);
}

// The home screen after a swipe up is drawn from the bottom up, following the swipe. There's no
// RAM for a whole frame, so LVGL draws (and sends) the screen in strips, top to bottom, which looks like the screen
// arriving from the top. On the next refresh with a full-screen area (the new screen), that area becomes strips
// listed bottom first: LVGL draws them in list order (and doesn't join strips that only touch).
static constexpr int BOTTOM_UP_STRIPS = 6;
static constexpr int BOTTOM_UP_WAIT_FRAMES = 10; // The home screen is loaded within this many refreshes, or never
static int bottom_up_frames_left = 0;

static void on_refresh_bottom_up(lv_event_t *event)
{
    lv_display_t *disp = static_cast<lv_display_t *>(lv_event_get_target(event));
    const int32_t w = lv_display_get_horizontal_resolution(disp);
    const int32_t h = lv_display_get_vertical_resolution(disp);
    bool full = false;
    for (uint32_t i = 0; i < disp->inv_p; i++) {
        const lv_area_t &a = disp->inv_areas[i];
        if ((disp->inv_area_joined[i] == 0) && (a.x1 <= 0) && (a.y1 <= 0) && (a.x2 >= w - 1) && (a.y2 >= h - 1)) {
            full = true;
            break;
        }
    }
    if (full && (BOTTOM_UP_STRIPS <= LV_INV_BUF_SIZE)) {
        // Strips start on even rows: the panel takes areas only that way (the BSP's rounder does it for areas LVGL
        // invalidates itself, not for these)
        auto boundary = [h](int i) {
            return (i >= BOTTOM_UP_STRIPS) ? h : ((h * i / BOTTOM_UP_STRIPS) & ~1);
        };
        disp->inv_p = 0;
        for (int i = BOTTOM_UP_STRIPS - 1; i >= 0; i--) {
            lv_area_t &a = disp->inv_areas[disp->inv_p];
            a.x1 = 0;
            a.x2 = w - 1;
            a.y1 = boundary(i);
            a.y2 = boundary(i + 1) - 1;
            disp->inv_area_joined[disp->inv_p] = 0;
            disp->inv_p++;
        }
    }
    if (full || (--bottom_up_frames_left <= 0)) {
        lv_display_remove_event_cb_with_user_data(disp, on_refresh_bottom_up, nullptr);
        bottom_up_frames_left = 0;
    }
}

static void refresh_next_screen_bottom_up(void)
{
    lv_display_t *disp = lv_display_get_default();
    if ((disp == nullptr) || (bottom_up_frames_left > 0)) {
        return;
    }
    bottom_up_frames_left = BOTTOM_UP_WAIT_FRAMES;
    lv_display_add_event_cb(disp, on_refresh_bottom_up, LV_EVENT_REFR_START, nullptr);
}

// Power key as a back button (called by the power manager with the LVGL lock held): an open app closes (back to the
// home screen), the home screen opens the watch; in the watch it returns false and the watch goes to sleep
static bool on_power_key(void)
{
    auto *app = phone_instance->getManager().getActiveApp();
    if (app == nullptr) {
        return (watch_app_id >= 0) && send_app_event(watch_app_id, systems::base::Context::AppEventType::START);
    }
    if (app->getId() == watch_app_id) {
        return false;
    }
    return send_app_event(app->getId(), systems::base::Context::AppEventType::STOP);
}

extern "C" void app_main(void)
{
    ESP_UTILS_LOGI("Display ESP-Brookesia phone demo");

    /* Power rails first: the PMU keeps its settings across power-off, so restore anything left switched off */
    pmu_ensure_rails();

    /* NVS: time zone, BLE pairing */
    esp_err_t nvs_ret = nvs_flash_init();
    if ((nvs_ret == ESP_ERR_NVS_NO_FREE_PAGES) || (nvs_ret == ESP_ERR_NVS_NEW_VERSION_FOUND)) {
        ESP_UTILS_CHECK_ERROR_EXIT(nvs_flash_erase(), "Erase NVS failed");
        nvs_ret = nvs_flash_init();
    }
    ESP_UTILS_CHECK_ERROR_EXIT(nvs_ret, "Init NVS failed");

    /* Time zone + time from the RTC chip, before the UI shows any time; the paired phone can set it via BLE */
    time_sync_start();
    ble_sync_set_time_handler([](int64_t utc, const char *tz) {
        return time_sync_set(static_cast<time_t>(utc), tz);
    });

    /* The watch's name (home screen title); the paired phone can change it via BLE */
    watch_name_init(INITIAL_WATCH_NAME);
    ble_sync_set_name_handler([](const char *name) {
        return watch_name_set(name);
    });
    ble_sync_get_name_handler([]() {
        return watch_name_get();
    });

    /* User files (photos, music, watch faces); before the UI, since the boot app (the watch faces) reads them */
    if (!file_store_mount()) {
        ESP_UTILS_LOGE("File store not available");
    }

    /* Watch faces (the "Ur" app): uploaded faces and their order come from the paired phone via BLE */
    watch_faces_init();
    // Home after a swipe up (from any app): the home screen appears from the bottom
    systems::phone::Manager::on_going_home = refresh_next_screen_bottom_up;
    watch_faces_set_home_handler([]() {
        if (phone_instance != nullptr) {
            phone_instance->sendNavigateEvent(systems::base::Manager::NavigateType::HOME);
        }
    });
    watch_faces_set_battery_source([]() {
        PmuBattery battery;
        return (pmu_battery(&battery) && battery.present) ? battery.percent : -1;
    });
    static const ble_sync_face_handlers_t face_handlers = {
        .get_state = watch_faces_get_state,
        .set_order = watch_faces_set_order,
        .set_birthday = watch_faces_set_birthday,
        .features_json = watch_faces_features_json(),
    };
    ble_sync_set_face_handlers(&face_handlers);

    bsp_display_cfg_t cfg = {
        .lvgl_port_cfg = LVGL_PORT_INIT_CONFIG(),
    };
    ESP_UTILS_CHECK_NULL_EXIT(bsp_display_start_with_config(&cfg), "Start display failed");
    ESP_UTILS_CHECK_ERROR_EXIT(bsp_display_backlight_on(), "Turn on display backlight failed");

    /* Configure GUI lock */
    LvLock::registerCallbacks([](int timeout_ms) {
        if (timeout_ms < 0) {
            timeout_ms = 0;
        } else if (timeout_ms == 0) {
            timeout_ms = 1;
        }
        ESP_UTILS_CHECK_FALSE_RETURN(bsp_display_lock(timeout_ms), false, "Lock failed");

        return true;
    }, []() {
        bsp_display_unlock();

        return true;
    });

    /* Create a phone object */
    Phone *phone = new (std::nothrow) Phone();
    ESP_UTILS_CHECK_NULL_EXIT(phone, "Create phone failed");

    /* Try using a stylesheet that corresponds to the resolution */
    if ((BSP_LCD_H_RES == 410) && (BSP_LCD_V_RES == 502)) {
        Stylesheet *stylesheet = new (std::nothrow) Stylesheet(STYLESHEET_410_502_DARK);
        ESP_UTILS_CHECK_NULL_EXIT(stylesheet, "Create stylesheet failed");

        ESP_UTILS_LOGI("Using stylesheet (%s)", stylesheet->core.name);
        ESP_UTILS_CHECK_FALSE_EXIT(phone->addStylesheet(stylesheet), "Add stylesheet failed");
        ESP_UTILS_CHECK_FALSE_EXIT(phone->activateStylesheet(stylesheet), "Activate stylesheet failed");
        delete stylesheet;
    }

    {
        // When operating on non-GUI tasks, should acquire a lock before operating on LVGL
        LvLockGuard gui_guard;

        /* Begin the phone */
        ESP_UTILS_CHECK_FALSE_EXIT(phone->begin(), "Begin failed");
        // assert(phone->getDisplay().showContainerBorder() && "Show container border failed");

        /* Init and install apps from registry */
        std::vector<systems::base::Manager::RegistryAppInfo> inited_apps;
        ESP_UTILS_CHECK_FALSE_EXIT(phone->initAppFromRegistry(inited_apps), "Init app registry failed");
        std::vector<std::string> app_order(std::begin(APP_ORDER), std::end(APP_ORDER));
        ESP_UTILS_CHECK_FALSE_EXIT(phone->installAppFromRegistry(inited_apps, &app_order),
                                   "Install app registry failed");

        lv_obj_t *title = lv_label_create(phone->getDisplay().getMainScreen());
        lv_obj_set_width(title, HOME_TITLE_WIDTH);
        lv_label_set_long_mode(title, LV_LABEL_LONG_DOT);
        lv_obj_set_style_text_align(title, LV_TEXT_ALIGN_CENTER, 0);
        lv_obj_set_style_text_font(title, &watch_font_danish_28, 0);
        watch_name_attach_label(title);
        lv_obj_set_style_text_color(title, lv_color_white(), 0);
        lv_obj_align(title, LV_ALIGN_TOP_MID, 0, HOME_TITLE_Y);

        /* Start in the boot app instead of the launcher */
        phone_instance = phone;
        bool boot_app_started = false;
        for (auto &[name, app] : inited_apps) {
            if ((name == BOOT_APP_NAME) && app) {
                watch_app_id = app->getId();
                boot_app_started = send_app_event(watch_app_id, systems::base::Context::AppEventType::START);
                break;
            }
        }
        if (!boot_app_started) {
            ESP_UTILS_LOGW("Boot app '%s' not started, staying on the launcher", BOOT_APP_NAME);
        }

        /* Stopur and Tidstagning: timers keep running when the apps close, and ring with a banner over any screen */
        watch_tools_init();

        /* Bluetooth sync while charging, without opening Synk (the phone app connects by itself): only on the watch
         * face or an empty home screen, where nothing else needs the RAM (BLE and the MP3 decoder don't both fit), and
         * never while music plays or is paused. Checked often, so BLE is gone right after another app opens.
         * Starting/stopping happens on its own task (ble_background.cpp). Unplugging while asleep: power_manager.cpp. */
        ble_background_start();
        lv_timer_create([](lv_timer_t *) {
            auto &manager = phone_instance->getManager();
            auto *app = manager.getActiveApp();
            // On the face, or at home with nothing paused but the face (another paused app still holds its memory).
            // Going face -> home -> face must not flip BLE (each start/stop takes a while)
            auto *paused = (manager.getRunningAppCount() > 0) ? manager.getRunningAppByIdenx(0) : nullptr;
            const bool quiet_screen = (app != nullptr) ? (app->getId() == watch_app_id)
                                                       : ((paused == nullptr) || (paused->getId() == watch_app_id));
            ble_background_want(pmu_vbus_present() && quiet_screen && !music_player_is_active());
        }, 500, nullptr);

        /* Create a timer to update the clock */
        lv_timer_create([](lv_timer_t *t) {
            time_t now;
            struct tm timeinfo;
            Phone *phone = (Phone *)t->user_data;

            ESP_UTILS_CHECK_NULL_EXIT(phone, "Invalid phone");

            time(&now);
            localtime_r(&now, &timeinfo);

            ESP_UTILS_CHECK_FALSE_EXIT(
                phone->getDisplay().getStatusBar()->setClock(timeinfo.tm_hour, timeinfo.tm_min),
                "Refresh status bar failed"
            );

            // Battery from the PMU's fuel gauge (first update shortly after boot, and right away on USB plug/unplug)
            static uint32_t seconds = BATTERY_UPDATE_S - 2;
            static bool last_vbus = false;
            seconds++;
            const bool vbus = pmu_vbus_present();
            if ((seconds % BATTERY_UPDATE_S == 0) || (vbus != last_vbus)) {
                last_vbus = vbus;
                PmuBattery battery;
                auto *status_bar = phone->getDisplay().getStatusBar();
                if (pmu_battery(&battery) && battery.present && (battery.percent >= 0)) {
                    status_bar->showBatteryIcon();
                    status_bar->setBatteryPercent(battery.charging, battery.percent);
                } else if (pmu_battery(&battery) && !battery.present) {
                    status_bar->hideBatteryIcon();
                }
            }
            if (seconds % STEPS_SAVE_S == 0) {
                step_counter_save();
            }
        }, 1000, phone);
    }

    ESP_UTILS_LOGI("Free internal heap after UI setup: %u KB (largest block %u KB)",
                   (unsigned)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024),
                   (unsigned)(heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL) / 1024));


    /* Step counter (accelerometer FIFO; keeps counting while asleep) */
    if (!step_counter_init()) {
        ESP_UTILS_LOGE("Step counter not available");
    }

    /* Audio chips (on the main 3.3 V rail) into low power until something plays audio */
    audio_power_down();

    /* MP3 playback (Musik); the audio hardware is only woken up when something plays */
    if (!music_player_init()) {
        ESP_UTILS_LOGE("Music player not available");
    }

    /* Power button: back (app → home → watch), then sleep; also sleep after a while idle on the home screen */
    // The PMU is on the I2C bus with the touch controller and the RTC; one failed transfer at boot shouldn't cost the
    // power button for the whole run
    bool pmu_ok = false;
    for (int attempt = 0; (attempt < 3) && !pmu_ok; attempt++) {
        if (attempt > 0) {
            vTaskDelay(pdMS_TO_TICKS(50));
        }
        pmu_ok = pmu_init();
    }
    if (pmu_ok) {
        power_manager_start(phone->getDisplay().getMainScreen(), on_power_key);
    } else {
        ESP_UTILS_LOGE("Power button not available, sleep disabled");
    }

    if constexpr (EXAMPLE_SHOW_MEM_INFO) {
        esp_utils::thread_config_guard thread_config({
            .name = "mem_info",
            .stack_size = 4096,
        });
        boost::thread([ = ]() {
            char buffer[128];    /* Make sure buffer is enough for `sprintf` */
            size_t internal_free = 0;
            size_t internal_total = 0;
            size_t external_free = 0;
            size_t external_total = 0;

            while (1) {
                internal_free = heap_caps_get_free_size(MALLOC_CAP_INTERNAL);
                internal_total = heap_caps_get_total_size(MALLOC_CAP_INTERNAL);
                external_free = heap_caps_get_free_size(MALLOC_CAP_SPIRAM);
                external_total = heap_caps_get_total_size(MALLOC_CAP_SPIRAM);
                sprintf(buffer,
                        "\t           Biggest /     Free /    Total\n"
                        "\t  SRAM : [%8d / %8d / %8d]\n"
                        "\t PSRAM : [%8d / %8d / %8d]",
                        heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL), internal_free, internal_total,
                        heap_caps_get_largest_free_block(MALLOC_CAP_SPIRAM), external_free, external_total);
                ESP_UTILS_LOGI("\n%s", buffer);

                {
                    LvLockGuard gui_guard;
                    ESP_UTILS_CHECK_FALSE_EXIT(
                        phone->getDisplay().getRecentsScreen()->setMemoryLabel(
                            internal_free / 1024, internal_total / 1024, external_free / 1024, external_total / 1024
                        ), "Set memory label failed"
                    );
                }

                boost::this_thread::sleep_for(boost::chrono::seconds(5));
            }
        }).detach();
    }
}