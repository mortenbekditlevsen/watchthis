/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include "lvgl.h"
#include "nvs.h"
#include "bsp/display.h"
#include "esp_brookesia.hpp"
#ifdef ESP_UTILS_LOG_TAG
#   undef ESP_UTILS_LOG_TAG
#endif
#define ESP_UTILS_LOG_TAG "BS:Settings"
#include "esp_lib_utils.h"
#include "settings.h"
#include "esp_brookesia_app_settings.hpp"

#define APP_NAME "Indstillinger"

using namespace esp_brookesia::systems;

LV_IMG_DECLARE(esp_brookesia_app_icon_launcher_settings_112_112);

namespace {

constexpr const char *NVS_NAMESPACE = "settings";
constexpr const char *NVS_BRIGHTNESS = "brightness";
// Below this the screen is hard to read outdoors, and at 0 it would look off
constexpr int MIN_BRIGHTNESS = 5;

void save_brightness(int percent)
{
    nvs_handle_t nvs;
    if (nvs_open(NVS_NAMESPACE, NVS_READWRITE, &nvs) != ESP_OK) {
        ESP_UTILS_LOGW("Can't save the brightness");
        return;
    }
    nvs_set_u8(nvs, NVS_BRIGHTNESS, (uint8_t)percent);
    nvs_commit(nvs);
    nvs_close(nvs);
}

} // namespace

extern "C" void settings_restore(void)
{
    nvs_handle_t nvs;
    uint8_t percent = 0;
    if (nvs_open(NVS_NAMESPACE, NVS_READONLY, &nvs) == ESP_OK) {
        if ((nvs_get_u8(nvs, NVS_BRIGHTNESS, &percent) == ESP_OK) && (percent >= MIN_BRIGHTNESS) && (percent <= 100)) {
            bsp_display_backlight_level_set(percent);
        }
        nvs_close(nvs);
    }
}

namespace esp_brookesia::apps {

Settings *Settings::_instance = nullptr;

Settings *Settings::requestInstance()
{
    if (_instance == nullptr) {
        _instance = new Settings();
    }
    return _instance;
}

Settings::Settings():
    App(APP_NAME, &esp_brookesia_app_icon_launcher_settings_112_112, true, false, false)
{
}

Settings::~Settings()
{
}

bool Settings::run(void)
{
    ESP_UTILS_LOGD("Run");

    // Everything created here is recorded by the core and cleaned up when the app closes
    lv_obj_t *screen = lv_screen_active();
    lv_obj_set_style_bg_color(screen, lv_color_black(), 0);
    lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);
    lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t *title = lv_label_create(screen);
    lv_label_set_text(title, APP_NAME);
    lv_obj_set_style_text_font(title, &lv_font_montserrat_28, 0);
    lv_obj_set_style_text_color(title, lv_color_white(), 0);
    lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 24);

    lv_obj_t *label = lv_label_create(screen);
    lv_label_set_text(label, LV_SYMBOL_IMAGE "  Lysstyrke");
    lv_obj_set_style_text_font(label, &lv_font_montserrat_22, 0);
    lv_obj_set_style_text_color(label, lv_color_hex(0xCCCCCC), 0);
    lv_obj_align(label, LV_ALIGN_TOP_LEFT, 40, 110);

    _value = lv_label_create(screen);
    lv_obj_set_style_text_font(_value, &lv_font_montserrat_22, 0);
    lv_obj_set_style_text_color(_value, lv_color_white(), 0);
    lv_obj_align(_value, LV_ALIGN_TOP_RIGHT, -40, 110);

    // A thick slider, easy to drag with a finger
    lv_obj_t *slider = lv_slider_create(screen);
    lv_obj_set_size(slider, 300, 24);
    lv_obj_align(slider, LV_ALIGN_TOP_MID, 0, 170);
    lv_slider_set_range(slider, MIN_BRIGHTNESS, 100);
    lv_slider_set_value(slider, bsp_display_backlight_level_get(), LV_ANIM_OFF);
    lv_obj_set_style_bg_color(slider, lv_color_hex(0x333333), LV_PART_MAIN);
    lv_obj_set_style_bg_color(slider, lv_color_hex(0xFFB020), LV_PART_INDICATOR);
    lv_obj_set_style_bg_color(slider, lv_color_white(), LV_PART_KNOB);
    lv_obj_set_style_pad_all(slider, 8, LV_PART_KNOB);
    // A drag that wanders up or down still moves the slider (not a gesture)
    lv_obj_remove_flag(slider, LV_OBJ_FLAG_GESTURE_BUBBLE);
    lv_obj_add_event_cb(slider, onBrightnessChanged, LV_EVENT_VALUE_CHANGED, this);
    lv_obj_add_event_cb(slider, onBrightnessReleased, LV_EVENT_RELEASED, this);
    lv_label_set_text_fmt(_value, "%d %%", (int)lv_slider_get_value(slider));

    return true;
}

bool Settings::back(void)
{
    ESP_UTILS_LOGD("Back");

    ESP_UTILS_CHECK_FALSE_RETURN(notifyCoreClosed(), false, "Notify core closed failed");

    return true;
}

bool Settings::close(void)
{
    ESP_UTILS_LOGD("Close");

    _value = nullptr;

    return true;
}

void Settings::onBrightnessChanged(lv_event_t *e)
{
    // Live while dragging
    Settings *app = static_cast<Settings *>(lv_event_get_user_data(e));
    const int percent = lv_slider_get_value(static_cast<lv_obj_t *>(lv_event_get_target(e)));
    bsp_display_backlight_level_set(percent);
    if (app->_value != nullptr) {
        lv_label_set_text_fmt(app->_value, "%d %%", percent);
    }
}

void Settings::onBrightnessReleased(lv_event_t *e)
{
    // Saved once the finger lifts (not on every step)
    save_brightness(lv_slider_get_value(static_cast<lv_obj_t *>(lv_event_get_target(e))));
}

ESP_UTILS_REGISTER_PLUGIN_WITH_CONSTRUCTOR(systems::base::App, Settings, APP_NAME, []()
{
    return std::shared_ptr<Settings>(Settings::requestInstance(), [](Settings * p) {});
})

} // namespace esp_brookesia::apps
