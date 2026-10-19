/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include "step_counter.h"
#include "watch_fonts.h"
#include "lvgl.h"
#include "esp_brookesia.hpp"
#ifdef ESP_UTILS_LOG_TAG
#   undef ESP_UTILS_LOG_TAG
#endif
#define ESP_UTILS_LOG_TAG "BS:Steps"
#include "esp_lib_utils.h"
#include "esp_brookesia_app_steps.hpp"

#define APP_NAME "Skridt"

constexpr uint32_t STEP_GOAL = 6000;
constexpr uint32_t UPDATE_MS = 1000;
constexpr int32_t ARC_SIZE = 300;
constexpr uint32_t ARC_COLOR = 0x45C46A;    // Same green as the launcher icon

using namespace esp_brookesia::systems;

LV_IMG_DECLARE(esp_brookesia_app_icon_launcher_steps_112_112);

namespace esp_brookesia::apps {

Steps *Steps::_instance = nullptr;

Steps *Steps::requestInstance()
{
    if (_instance == nullptr) {
        _instance = new Steps();
    }
    return _instance;
}

Steps::Steps():
    App(APP_NAME, &esp_brookesia_app_icon_launcher_steps_112_112, true, false, false)
{
}

Steps::~Steps()
{
}

bool Steps::run(void)
{
    ESP_UTILS_LOGD("Run");

    // Everything created here is recorded by the core and cleaned up when the app closes
    lv_obj_t *screen = lv_screen_active();
    lv_obj_set_style_bg_color(screen, lv_color_black(), 0);
    lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);
    lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE);

    // Progress towards the daily goal
    _arc = lv_arc_create(screen);
    lv_obj_set_size(_arc, ARC_SIZE, ARC_SIZE);
    lv_obj_align(_arc, LV_ALIGN_CENTER, 0, -30);
    lv_arc_set_bg_angles(_arc, 135, 45);
    lv_arc_set_range(_arc, 0, STEP_GOAL);
    lv_obj_remove_style(_arc, nullptr, LV_PART_KNOB);
    lv_obj_remove_flag(_arc, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_style_arc_width(_arc, 18, LV_PART_MAIN);
    lv_obj_set_style_arc_width(_arc, 18, LV_PART_INDICATOR);
    lv_obj_set_style_arc_color(_arc, lv_color_hex(0x222222), LV_PART_MAIN);
    lv_obj_set_style_arc_color(_arc, lv_color_hex(ARC_COLOR), LV_PART_INDICATOR);

    _today = lv_label_create(screen);
    lv_obj_set_style_text_font(_today, &lv_font_montserrat_44, 0);
    lv_obj_set_style_text_color(_today, lv_color_white(), 0);
    lv_obj_align(_today, LV_ALIGN_CENTER, 0, -40);

    lv_obj_t *unit = lv_label_create(screen);
    lv_label_set_text_fmt(unit, "skridt af %u", (unsigned)STEP_GOAL);
    lv_obj_set_style_text_font(unit, &watch_font_danish_20, 0);
    lv_obj_set_style_text_color(unit, lv_color_hex(0xAAAAAA), 0);
    lv_obj_align(unit, LV_ALIGN_CENTER, 0, 10);

    _yesterday = lv_label_create(screen);
    lv_obj_set_style_text_font(_yesterday, &watch_font_danish_20, 0);
    lv_obj_set_style_text_color(_yesterday, lv_color_hex(0x888888), 0);
    lv_obj_align(_yesterday, LV_ALIGN_BOTTOM_MID, 0, -50);

    update();
    lv_timer_create(onTimer, UPDATE_MS, this);

    return true;
}

bool Steps::back(void)
{
    ESP_UTILS_LOGD("Back");

    ESP_UTILS_CHECK_FALSE_RETURN(notifyCoreClosed(), false, "Notify core closed failed");

    return true;
}

bool Steps::close(void)
{
    ESP_UTILS_LOGD("Close");

    // The core deletes the recorded timer and objects itself
    _arc = _today = _yesterday = nullptr;

    return true;
}

void Steps::update(void)
{
    const uint32_t today = step_counter_today();
    lv_arc_set_value(_arc, LV_MIN(today, STEP_GOAL));
    lv_label_set_text_fmt(_today, "%u", (unsigned)today);
    lv_label_set_text_fmt(_yesterday, "I går: %u skridt", (unsigned)step_counter_yesterday());
}

void Steps::onTimer(lv_timer_t *timer)
{
    Steps *app = static_cast<Steps *>(lv_timer_get_user_data(timer));
    if (app->_today != nullptr) {
        app->update();
    }
}

ESP_UTILS_REGISTER_PLUGIN_WITH_CONSTRUCTOR(systems::base::App, Steps, APP_NAME, []()
{
    return std::shared_ptr<Steps>(Steps::requestInstance(), [](Steps * p) {});
})

} // namespace esp_brookesia::apps
