/*
 * SPDX-FileCopyrightText: 2023-2025 Espressif Systems (Shanghai) CO LTD
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#include <cstdio>
#include <cstring>
#include <ctime>
#include <sys/time.h>
#include "lvgl.h"
#include "esp_brookesia.hpp"
#ifdef ESP_UTILS_LOG_TAG
#   undef ESP_UTILS_LOG_TAG
#endif
#define ESP_UTILS_LOG_TAG "BS:Squareline"
#include "esp_lib_utils.h"
#include "ui/ui.h"
#include "esp_brookesia_app_squareline_demo.hpp"

#define APP_NAME "Squareline"

using namespace std;
using namespace esp_brookesia::gui;
using namespace esp_brookesia::systems;

LV_IMG_DECLARE(esp_brookesia_app_icon_launcher_squareline_112_112);

namespace {

constexpr uint32_t CLOCK_UPDATE_PERIOD_MS = 100;
// Anything before this means SNTP has not synced yet and the clock still counts from 1970-01-01
constexpr int CLOCK_MIN_VALID_YEAR = 2024;

// Tick at which the screen-load animations of the hour/minute hands are done; until then they own the rotation
uint32_t clock_hands_anim_end_tick = 0;

const char *const WEEKDAY_NAMES[] = {"Søn", "Man", "Tir", "Ons", "Tor", "Fre", "Lør"};
// Danish abbreviations; "maj" is the full word, so it has no period
const char *const MONTH_NAMES[] = {
    "jan.", "feb.", "mar.", "apr.", "maj", "jun.", "jul.", "aug.", "sep.", "okt.", "nov.", "dec."
};

// Hand images point to 12 o'clock at rotation 0; rotation is in 0.1 degree units
int32_t clock_hour_angle(const struct tm &t)
{
    return (t.tm_hour % 12) * 300 + t.tm_min * 5;
}

int32_t clock_min_angle(const struct tm &t)
{
    return t.tm_min * 60 + t.tm_sec;
}

void clock_get_local_time(struct tm &t, suseconds_t *usec = nullptr)
{
    struct timeval tv;

    gettimeofday(&tv, nullptr);
    localtime_r(&tv.tv_sec, &t);
    if (usec != nullptr) {
        *usec = tv.tv_usec;
    }
}

void label_set_text_if_changed(lv_obj_t *label, const char *text)
{
    if (strcmp(lv_label_get_text(label), text) != 0) {
        lv_label_set_text(label, text);
    }
}

void clock_update(lv_timer_t *timer)
{
    struct tm t;
    suseconds_t usec;
    char buf[32];

    clock_get_local_time(t, &usec);

    if (t.tm_year + 1900 < CLOCK_MIN_VALID_YEAR) {
        label_set_text_if_changed(ui_clock_label_clock_number, "--:--");
        label_set_text_if_changed(ui_clock_small_label_date, "");
    } else {
        snprintf(buf, sizeof(buf), "%02d:%02d", t.tm_hour, t.tm_min);
        label_set_text_if_changed(ui_clock_label_clock_number, buf);
        snprintf(buf, sizeof(buf), "%s %d. %s", WEEKDAY_NAMES[t.tm_wday], t.tm_mday, MONTH_NAMES[t.tm_mon]);
        label_set_text_if_changed(ui_clock_small_label_date, buf);
    }

    if ((int32_t)(lv_tick_get() - clock_hands_anim_end_tick) >= 0) {
        lv_image_set_rotation(ui_clock_image_hour, clock_hour_angle(t));
        lv_image_set_rotation(ui_clock_image_min, clock_min_angle(t));
    }
    // Sweep the second hand in 0.6 degree steps
    lv_image_set_rotation(ui_clock_image_sec, t.tm_sec * 60 + (usec / 100000) * 6);
}

} // namespace

namespace esp_brookesia::apps {

SquarelineDemo *SquarelineDemo::_instance = nullptr;

SquarelineDemo *SquarelineDemo::requestInstance(bool use_status_bar, bool use_navigation_bar)
{
    if (_instance == nullptr) {
        _instance = new SquarelineDemo(use_status_bar, use_navigation_bar);
    }
    return _instance;
}

SquarelineDemo::SquarelineDemo(bool use_status_bar, bool use_navigation_bar):
    App(APP_NAME, &esp_brookesia_app_icon_launcher_squareline_112_112, false, use_status_bar, use_navigation_bar)
{
}

SquarelineDemo::~SquarelineDemo()
{
}

bool SquarelineDemo::run(void)
{
    ESP_UTILS_LOGD("Run");

    // Create all UI resources here
    phone_app_squareline_ui_init();

    // Drive the clock screen from the system time (synced via SNTP); the timer is recorded as an app resource and
    // deleted when the app closes
    lv_obj_set_style_text_font(ui_clock_small_label_date, &ui_font_danish_18, LV_PART_MAIN);
    clock_hands_anim_end_tick = 0;
    clock_update(nullptr);
    lv_timer_create(clock_update, CLOCK_UPDATE_PERIOD_MS, nullptr);

    return true;
}

bool SquarelineDemo::back(void)
{
    ESP_UTILS_LOGD("Back");

    // If the app needs to exit, call notifyCoreClosed() to notify the core to close the app
    ESP_UTILS_CHECK_FALSE_RETURN(notifyCoreClosed(), false, "Notify core closed failed");

    return true;
}

// bool SquarelineDemo::close(void)
// {
//     ESP_UTILS_LOGD("Close");

//     /* Do some operations here if needed */

//     return true;
// }

// bool SquarelineDemo::init()
// {
//     ESP_UTILS_LOGD("Init");

//     /* Do some initialization here if needed */

//     return true;
// }

// bool SquarelineDemo::deinit()
// {
//     ESP_UTILS_LOGD("Deinit");

//     /* Do some deinitialization here if needed */

//     return true;
// }

// bool SquarelineDemo::pause()
// {
//     ESP_UTILS_LOGD("Pause");

//     /* Do some operations here if needed */

//     return true;
// }

// bool SquarelineDemo::resume()
// {
//     ESP_UTILS_LOGD("Resume");

//     /* Do some operations here if needed */

//     return true;
// }

// bool SquarelineDemo::cleanResource()
// {
//     ESP_UTILS_LOGD("Clean resource");

//     /* Do some cleanup here if needed */

//     return true;
// }

extern "C" {

    /**
     * The following functions are generated by Squareline and records resources before and after creating animations,
     * allowing for automatic cleanup of animation resources when the app exits. This prevents errors that may occur when
     * animations call UI elements that have already been cleaned up.
     *
     */
    void upanim_Animation(lv_obj_t *TargetObject, int delay)
    {
        ui_anim_user_data_t *PropertyAnimation_0_user_data = (ui_anim_user_data_t *)lv_malloc(sizeof(ui_anim_user_data_t));
        PropertyAnimation_0_user_data->target = TargetObject;
        PropertyAnimation_0_user_data->val = -1;
        lv_anim_t PropertyAnimation_0;
        lv_anim_init(&PropertyAnimation_0);
        lv_anim_set_time(&PropertyAnimation_0, 200);
        lv_anim_set_user_data(&PropertyAnimation_0, PropertyAnimation_0_user_data);
        lv_anim_set_custom_exec_cb(&PropertyAnimation_0, _ui_anim_callback_set_y);
        lv_anim_set_values(&PropertyAnimation_0, -30, 0);
        lv_anim_set_path_cb(&PropertyAnimation_0, lv_anim_path_ease_out);
        lv_anim_set_delay(&PropertyAnimation_0, delay + 0);
        lv_anim_set_deleted_cb(&PropertyAnimation_0, _ui_anim_callback_free_user_data);
        lv_anim_set_playback_time(&PropertyAnimation_0, 0);
        lv_anim_set_playback_delay(&PropertyAnimation_0, 0);
        lv_anim_set_repeat_count(&PropertyAnimation_0, 0);
        lv_anim_set_repeat_delay(&PropertyAnimation_0, 0);
        lv_anim_set_early_apply(&PropertyAnimation_0, false);
        lv_anim_set_get_value_cb(&PropertyAnimation_0, &_ui_anim_callback_get_y);

        ESP_UTILS_CHECK_FALSE_EXIT(
            SquarelineDemo::requestInstance()->startRecordResource(), "Start record resource failed"
        );
        lv_anim_start(&PropertyAnimation_0);
        ESP_UTILS_CHECK_FALSE_EXIT(
            SquarelineDemo::requestInstance()->endRecordResource(), "End record resource failed"
        );

        ui_anim_user_data_t *PropertyAnimation_1_user_data = (ui_anim_user_data_t *)lv_malloc(sizeof(ui_anim_user_data_t));
        PropertyAnimation_1_user_data->target = TargetObject;
        PropertyAnimation_1_user_data->val = -1;
        lv_anim_t PropertyAnimation_1;
        lv_anim_init(&PropertyAnimation_1);
        lv_anim_set_time(&PropertyAnimation_1, 100);
        lv_anim_set_user_data(&PropertyAnimation_1, PropertyAnimation_1_user_data);
        lv_anim_set_custom_exec_cb(&PropertyAnimation_1, _ui_anim_callback_set_opacity);
        lv_anim_set_values(&PropertyAnimation_1, 0, 255);
        lv_anim_set_path_cb(&PropertyAnimation_1, lv_anim_path_linear);
        lv_anim_set_delay(&PropertyAnimation_1, delay + 0);
        lv_anim_set_deleted_cb(&PropertyAnimation_1, _ui_anim_callback_free_user_data);
        lv_anim_set_playback_time(&PropertyAnimation_1, 0);
        lv_anim_set_playback_delay(&PropertyAnimation_1, 0);
        lv_anim_set_repeat_count(&PropertyAnimation_1, 0);
        lv_anim_set_repeat_delay(&PropertyAnimation_1, 0);
        lv_anim_set_early_apply(&PropertyAnimation_1, true);

        ESP_UTILS_CHECK_FALSE_EXIT(
            SquarelineDemo::requestInstance()->startRecordResource(), "Start record resource failed"
        );
        lv_anim_start(&PropertyAnimation_1);
        ESP_UTILS_CHECK_FALSE_EXIT(
            SquarelineDemo::requestInstance()->endRecordResource(), "End record resource failed"
        );

    }
    void hour_Animation(lv_obj_t *TargetObject, int delay)
    {
        ui_anim_user_data_t *PropertyAnimation_0_user_data = (ui_anim_user_data_t *)lv_malloc(sizeof(ui_anim_user_data_t));
        PropertyAnimation_0_user_data->target = TargetObject;
        PropertyAnimation_0_user_data->val = -1;
        lv_anim_t PropertyAnimation_0;
        lv_anim_init(&PropertyAnimation_0);
        lv_anim_set_time(&PropertyAnimation_0, 1000);
        lv_anim_set_user_data(&PropertyAnimation_0, PropertyAnimation_0_user_data);
        lv_anim_set_custom_exec_cb(&PropertyAnimation_0, _ui_anim_callback_set_image_angle);
        struct tm t;
        clock_get_local_time(t);
        lv_anim_set_values(&PropertyAnimation_0, 0, clock_hour_angle(t));
        clock_hands_anim_end_tick = lv_tick_get() + delay + 1000;
        lv_anim_set_path_cb(&PropertyAnimation_0, lv_anim_path_ease_out);
        lv_anim_set_delay(&PropertyAnimation_0, delay + 0);
        lv_anim_set_deleted_cb(&PropertyAnimation_0, _ui_anim_callback_free_user_data);
        lv_anim_set_playback_time(&PropertyAnimation_0, 0);
        lv_anim_set_playback_delay(&PropertyAnimation_0, 0);
        lv_anim_set_repeat_count(&PropertyAnimation_0, 0);
        lv_anim_set_repeat_delay(&PropertyAnimation_0, 0);
        lv_anim_set_early_apply(&PropertyAnimation_0, false);

        ESP_UTILS_CHECK_FALSE_EXIT(
            SquarelineDemo::requestInstance()->startRecordResource(), "Start record resource failed"
        );
        lv_anim_start(&PropertyAnimation_0);
        ESP_UTILS_CHECK_FALSE_EXIT(
            SquarelineDemo::requestInstance()->endRecordResource(), "End record resource failed"
        );

        ui_anim_user_data_t *PropertyAnimation_1_user_data = (ui_anim_user_data_t *)lv_malloc(sizeof(ui_anim_user_data_t));
        PropertyAnimation_1_user_data->target = TargetObject;
        PropertyAnimation_1_user_data->val = -1;
        lv_anim_t PropertyAnimation_1;
        lv_anim_init(&PropertyAnimation_1);
        lv_anim_set_time(&PropertyAnimation_1, 300);
        lv_anim_set_user_data(&PropertyAnimation_1, PropertyAnimation_1_user_data);
        lv_anim_set_custom_exec_cb(&PropertyAnimation_1, _ui_anim_callback_set_opacity);
        lv_anim_set_values(&PropertyAnimation_1, 0, 255);
        lv_anim_set_path_cb(&PropertyAnimation_1, lv_anim_path_linear);
        lv_anim_set_delay(&PropertyAnimation_1, delay + 0);
        lv_anim_set_deleted_cb(&PropertyAnimation_1, _ui_anim_callback_free_user_data);
        lv_anim_set_playback_time(&PropertyAnimation_1, 0);
        lv_anim_set_playback_delay(&PropertyAnimation_1, 0);
        lv_anim_set_repeat_count(&PropertyAnimation_1, 0);
        lv_anim_set_repeat_delay(&PropertyAnimation_1, 0);
        lv_anim_set_early_apply(&PropertyAnimation_1, true);

        ESP_UTILS_CHECK_FALSE_EXIT(
            SquarelineDemo::requestInstance()->startRecordResource(), "Start record resource failed"
        );
        lv_anim_start(&PropertyAnimation_1);
        ESP_UTILS_CHECK_FALSE_EXIT(
            SquarelineDemo::requestInstance()->endRecordResource(), "End record resource failed"
        );

    }
    void min_Animation(lv_obj_t *TargetObject, int delay)
    {
        ui_anim_user_data_t *PropertyAnimation_0_user_data = (ui_anim_user_data_t *)lv_malloc(sizeof(ui_anim_user_data_t));
        PropertyAnimation_0_user_data->target = TargetObject;
        PropertyAnimation_0_user_data->val = -1;
        lv_anim_t PropertyAnimation_0;
        lv_anim_init(&PropertyAnimation_0);
        lv_anim_set_time(&PropertyAnimation_0, 1000);
        lv_anim_set_user_data(&PropertyAnimation_0, PropertyAnimation_0_user_data);
        lv_anim_set_custom_exec_cb(&PropertyAnimation_0, _ui_anim_callback_set_image_angle);
        struct tm t;
        clock_get_local_time(t);
        lv_anim_set_values(&PropertyAnimation_0, 0, clock_min_angle(t));
        clock_hands_anim_end_tick = lv_tick_get() + delay + 1000;
        lv_anim_set_path_cb(&PropertyAnimation_0, lv_anim_path_ease_out);
        lv_anim_set_delay(&PropertyAnimation_0, delay + 0);
        lv_anim_set_deleted_cb(&PropertyAnimation_0, _ui_anim_callback_free_user_data);
        lv_anim_set_playback_time(&PropertyAnimation_0, 0);
        lv_anim_set_playback_delay(&PropertyAnimation_0, 0);
        lv_anim_set_repeat_count(&PropertyAnimation_0, 0);
        lv_anim_set_repeat_delay(&PropertyAnimation_0, 0);
        lv_anim_set_early_apply(&PropertyAnimation_0, false);

        ESP_UTILS_CHECK_FALSE_EXIT(
            SquarelineDemo::requestInstance()->startRecordResource(), "Start record resource failed"
        );
        lv_anim_start(&PropertyAnimation_0);
        ESP_UTILS_CHECK_FALSE_EXIT(
            SquarelineDemo::requestInstance()->endRecordResource(), "End record resource failed"
        );

        ui_anim_user_data_t *PropertyAnimation_1_user_data = (ui_anim_user_data_t *)lv_malloc(sizeof(ui_anim_user_data_t));
        PropertyAnimation_1_user_data->target = TargetObject;
        PropertyAnimation_1_user_data->val = -1;
        lv_anim_t PropertyAnimation_1;
        lv_anim_init(&PropertyAnimation_1);
        lv_anim_set_time(&PropertyAnimation_1, 200);
        lv_anim_set_user_data(&PropertyAnimation_1, PropertyAnimation_1_user_data);
        lv_anim_set_custom_exec_cb(&PropertyAnimation_1, _ui_anim_callback_set_opacity);
        lv_anim_set_values(&PropertyAnimation_1, 0, 255);
        lv_anim_set_path_cb(&PropertyAnimation_1, lv_anim_path_linear);
        lv_anim_set_delay(&PropertyAnimation_1, delay + 0);
        lv_anim_set_deleted_cb(&PropertyAnimation_1, _ui_anim_callback_free_user_data);
        lv_anim_set_playback_time(&PropertyAnimation_1, 0);
        lv_anim_set_playback_delay(&PropertyAnimation_1, 0);
        lv_anim_set_repeat_count(&PropertyAnimation_1, 0);
        lv_anim_set_repeat_delay(&PropertyAnimation_1, 0);
        lv_anim_set_early_apply(&PropertyAnimation_1, true);

        ESP_UTILS_CHECK_FALSE_EXIT(
            SquarelineDemo::requestInstance()->startRecordResource(), "Start record resource failed"
        );
        lv_anim_start(&PropertyAnimation_1);
        ESP_UTILS_CHECK_FALSE_EXIT(
            SquarelineDemo::requestInstance()->endRecordResource(), "End record resource failed"
        );

    }
    void sec_Animation(lv_obj_t *TargetObject, int delay)
    {
        ui_anim_user_data_t *PropertyAnimation_0_user_data = (ui_anim_user_data_t *)lv_malloc(sizeof(ui_anim_user_data_t));
        PropertyAnimation_0_user_data->target = TargetObject;
        PropertyAnimation_0_user_data->val = -1;
        lv_anim_t PropertyAnimation_0;
        lv_anim_init(&PropertyAnimation_0);
        lv_anim_set_time(&PropertyAnimation_0, 60000);
        lv_anim_set_user_data(&PropertyAnimation_0, PropertyAnimation_0_user_data);
        lv_anim_set_custom_exec_cb(&PropertyAnimation_0, _ui_anim_callback_set_image_angle);
        lv_anim_set_values(&PropertyAnimation_0, 0, 3600);
        lv_anim_set_path_cb(&PropertyAnimation_0, lv_anim_path_linear);
        lv_anim_set_delay(&PropertyAnimation_0, delay + 0);
        lv_anim_set_deleted_cb(&PropertyAnimation_0, _ui_anim_callback_free_user_data);
        lv_anim_set_playback_time(&PropertyAnimation_0, 0);
        lv_anim_set_playback_delay(&PropertyAnimation_0, 0);
        lv_anim_set_repeat_count(&PropertyAnimation_0, LV_ANIM_REPEAT_INFINITE);
        lv_anim_set_repeat_delay(&PropertyAnimation_0, 0);
        lv_anim_set_early_apply(&PropertyAnimation_0, false);

        ESP_UTILS_CHECK_FALSE_EXIT(
            SquarelineDemo::requestInstance()->startRecordResource(), "Start record resource failed"
        );
        lv_anim_start(&PropertyAnimation_0);
        ESP_UTILS_CHECK_FALSE_EXIT(
            SquarelineDemo::requestInstance()->endRecordResource(), "End record resource failed"
        );

        ui_anim_user_data_t *PropertyAnimation_1_user_data = (ui_anim_user_data_t *)lv_malloc(sizeof(ui_anim_user_data_t));
        PropertyAnimation_1_user_data->target = TargetObject;
        PropertyAnimation_1_user_data->val = -1;
        lv_anim_t PropertyAnimation_1;
        lv_anim_init(&PropertyAnimation_1);
        lv_anim_set_time(&PropertyAnimation_1, 1000);
        lv_anim_set_user_data(&PropertyAnimation_1, PropertyAnimation_1_user_data);
        lv_anim_set_custom_exec_cb(&PropertyAnimation_1, _ui_anim_callback_set_opacity);
        lv_anim_set_values(&PropertyAnimation_1, 0, 255);
        lv_anim_set_path_cb(&PropertyAnimation_1, lv_anim_path_linear);
        lv_anim_set_delay(&PropertyAnimation_1, delay + 0);
        lv_anim_set_deleted_cb(&PropertyAnimation_1, _ui_anim_callback_free_user_data);
        lv_anim_set_playback_time(&PropertyAnimation_1, 0);
        lv_anim_set_playback_delay(&PropertyAnimation_1, 0);
        lv_anim_set_repeat_count(&PropertyAnimation_1, 0);
        lv_anim_set_repeat_delay(&PropertyAnimation_1, 0);
        lv_anim_set_early_apply(&PropertyAnimation_1, true);

        ESP_UTILS_CHECK_FALSE_EXIT(
            SquarelineDemo::requestInstance()->startRecordResource(), "Start record resource failed"
        );
        lv_anim_start(&PropertyAnimation_1);
        ESP_UTILS_CHECK_FALSE_EXIT(
            SquarelineDemo::requestInstance()->endRecordResource(), "End record resource failed"
        );

    }
    void scrolldot_Animation(lv_obj_t *TargetObject, int delay)
    {
        ui_anim_user_data_t *PropertyAnimation_0_user_data = (ui_anim_user_data_t *)lv_malloc(sizeof(ui_anim_user_data_t));
        PropertyAnimation_0_user_data->target = TargetObject;
        PropertyAnimation_0_user_data->val = -1;
        lv_anim_t PropertyAnimation_0;
        lv_anim_init(&PropertyAnimation_0);
        lv_anim_set_time(&PropertyAnimation_0, 300);
        lv_anim_set_user_data(&PropertyAnimation_0, PropertyAnimation_0_user_data);
        lv_anim_set_custom_exec_cb(&PropertyAnimation_0, _ui_anim_callback_set_y);
        lv_anim_set_values(&PropertyAnimation_0, 30, -8);
        lv_anim_set_path_cb(&PropertyAnimation_0, lv_anim_path_ease_out);
        lv_anim_set_delay(&PropertyAnimation_0, delay + 0);
        lv_anim_set_deleted_cb(&PropertyAnimation_0, _ui_anim_callback_free_user_data);
        lv_anim_set_playback_time(&PropertyAnimation_0, 0);
        lv_anim_set_playback_delay(&PropertyAnimation_0, 0);
        lv_anim_set_repeat_count(&PropertyAnimation_0, 0);
        lv_anim_set_repeat_delay(&PropertyAnimation_0, 0);
        lv_anim_set_early_apply(&PropertyAnimation_0, true);

        ESP_UTILS_CHECK_FALSE_EXIT(
            SquarelineDemo::requestInstance()->startRecordResource(), "Start record resource failed"
        );
        lv_anim_start(&PropertyAnimation_0);
        ESP_UTILS_CHECK_FALSE_EXIT(
            SquarelineDemo::requestInstance()->endRecordResource(), "End record resource failed"
        );
    }

} // extern "C"

ESP_UTILS_REGISTER_PLUGIN_WITH_CONSTRUCTOR(systems::base::App, SquarelineDemo, APP_NAME, []()
{
    return std::shared_ptr<SquarelineDemo>(SquarelineDemo::requestInstance(), [](SquarelineDemo * p) {});
})

} // namespace esp_brookesia::apps
