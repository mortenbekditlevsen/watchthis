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
#include "watch_fonts.h"
#include "esp_brookesia_app_settings.hpp"

#define APP_NAME "Indstillinger"

using namespace esp_brookesia::systems;

LV_IMG_DECLARE(esp_brookesia_app_icon_launcher_settings_112_112);

namespace {

constexpr const char *NVS_NAMESPACE = "settings";
constexpr const char *NVS_BRIGHTNESS = "brightness";
constexpr const char *NVS_NIGHT_BRIGHTNESS = "night_bright";
constexpr const char *NVS_NIGHT_CLOCK = "night_clock";
// Below this the screen is hard to read outdoors, and at 0 it would look off
constexpr int MIN_BRIGHTNESS = 5;
// The night clock: dim (in the dark), but not off
constexpr int MIN_NIGHT_BRIGHTNESS = 1;
constexpr int MAX_NIGHT_BRIGHTNESS = 50;
constexpr int DEFAULT_NIGHT_BRIGHTNESS = 10;

int night_brightness = DEFAULT_NIGHT_BRIGHTNESS;
bool night_clock_enabled = true;    // On by default: it was there before the switch
void (*try_night_handler)(void) = nullptr;

void save(const char *key, int percent)
{
    nvs_handle_t nvs;
    if (nvs_open(NVS_NAMESPACE, NVS_READWRITE, &nvs) != ESP_OK) {
        ESP_UTILS_LOGW("Can't save %s", key);
        return;
    }
    nvs_set_u8(nvs, key, (uint8_t)percent);
    nvs_commit(nvs);
    nvs_close(nvs);
}

// A slider with its name above, its value to the right of the name
lv_obj_t *add_slider(lv_obj_t *screen, int32_t y, const char *name, int min, int max, int value, lv_obj_t **value_label)
{
    lv_obj_t *label = lv_label_create(screen);
    lv_label_set_text(label, name);
    lv_obj_set_style_text_font(label, &watch_font_danish_20, 0);
    lv_obj_set_style_text_color(label, lv_color_hex(0xCCCCCC), 0);
    lv_obj_align(label, LV_ALIGN_TOP_LEFT, 40, y);

    *value_label = lv_label_create(screen);
    lv_obj_set_style_text_font(*value_label, &watch_font_danish_20, 0);
    lv_obj_set_style_text_color(*value_label, lv_color_white(), 0);
    lv_obj_align(*value_label, LV_ALIGN_TOP_RIGHT, -40, y);
    lv_label_set_text_fmt(*value_label, "%d %%", value);

    // A thick slider, easy to drag with a finger
    lv_obj_t *slider = lv_slider_create(screen);
    lv_obj_set_size(slider, 300, 24);
    lv_obj_align(slider, LV_ALIGN_TOP_MID, 0, y + 50);
    lv_slider_set_range(slider, min, max);
    lv_slider_set_value(slider, value, LV_ANIM_OFF);
    lv_obj_set_style_bg_color(slider, lv_color_hex(0x333333), LV_PART_MAIN);
    lv_obj_set_style_bg_color(slider, lv_color_hex(0xFFB020), LV_PART_INDICATOR);
    lv_obj_set_style_bg_color(slider, lv_color_white(), LV_PART_KNOB);
    lv_obj_set_style_pad_all(slider, 8, LV_PART_KNOB);
    // A drag that wanders up or down still moves the slider (not a gesture)
    lv_obj_remove_flag(slider, LV_OBJ_FLAG_GESTURE_BUBBLE);
    return slider;
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
        if ((nvs_get_u8(nvs, NVS_NIGHT_BRIGHTNESS, &percent) == ESP_OK) && (percent >= MIN_NIGHT_BRIGHTNESS) &&
                (percent <= MAX_NIGHT_BRIGHTNESS)) {
            night_brightness = percent;
        }
        if (nvs_get_u8(nvs, NVS_NIGHT_CLOCK, &percent) == ESP_OK) {
            night_clock_enabled = (percent != 0);
        }
        nvs_close(nvs);
    }
}

extern "C" int settings_night_brightness(void)
{
    return night_brightness;
}

extern "C" bool settings_night_clock_enabled(void)
{
    return night_clock_enabled;
}

extern "C" void settings_set_try_night_handler(void (*try_night)(void))
{
    try_night_handler = try_night;
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

    lv_obj_t *slider = add_slider(screen, 90, "Lysstyrke", MIN_BRIGHTNESS, 100, bsp_display_backlight_level_get(),
                                  &_value);
    lv_obj_add_event_cb(slider, onBrightnessChanged, LV_EVENT_VALUE_CHANGED, this);
    lv_obj_add_event_cb(slider, onBrightnessReleased, LV_EVENT_RELEASED, this);

    // The night clock (the watch lying still on its left side): on or off
    lv_obj_t *night_label = lv_label_create(screen);
    lv_label_set_text(night_label, "Nattilstand");
    lv_obj_set_style_text_font(night_label, &watch_font_danish_20, 0);
    lv_obj_set_style_text_color(night_label, lv_color_hex(0xCCCCCC), 0);
    lv_obj_align(night_label, LV_ALIGN_TOP_LEFT, 40, 196);
    lv_obj_t *night_switch = lv_switch_create(screen);
    lv_obj_set_size(night_switch, 70, 38);
    lv_obj_align(night_switch, LV_ALIGN_TOP_RIGHT, -40, 188);
    lv_obj_set_style_bg_color(night_switch, lv_color_hex(0x333333), LV_PART_MAIN);
    lv_obj_set_style_bg_color(night_switch, lv_color_hex(0xFFB020), LV_PART_INDICATOR | LV_STATE_CHECKED);
    lv_obj_remove_flag(night_switch, LV_OBJ_FLAG_GESTURE_BUBBLE);
    if (night_clock_enabled) {
        lv_obj_add_state(night_switch, LV_STATE_CHECKED);
    }
    lv_obj_add_event_cb(night_switch, [](lv_event_t *e) {
        night_clock_enabled = lv_obj_has_state(static_cast<lv_obj_t *>(lv_event_get_target(e)), LV_STATE_CHECKED);
        save(NVS_NIGHT_CLOCK, night_clock_enabled ? 1 : 0);
    }, LV_EVENT_VALUE_CHANGED, nullptr);

    // The night clock has a brightness of its own: shown while dragging
    slider = add_slider(screen, 250, "Lysstyrke, nattilstand", MIN_NIGHT_BRIGHTNESS, MAX_NIGHT_BRIGHTNESS,
                        night_brightness, &_night_value);
    lv_obj_add_event_cb(slider, onNightBrightnessChanged, LV_EVENT_VALUE_CHANGED, this);
    lv_obj_add_event_cb(slider, onNightBrightnessReleased, LV_EVENT_RELEASED, this);
    lv_obj_add_event_cb(slider, onNightBrightnessReleased, LV_EVENT_PRESS_LOST, this);

    // Shows the night clock for a while (it normally only comes with the watch lying on its left side)
    lv_obj_t *button = lv_button_create(screen);
    lv_obj_set_style_bg_color(button, lv_color_hex(0x333333), 0);
    lv_obj_align(button, LV_ALIGN_TOP_MID, 0, 372);
    lv_obj_add_event_cb(button, [](lv_event_t *) {
        if (try_night_handler != nullptr) {
            try_night_handler();
        }
    }, LV_EVENT_CLICKED, nullptr);
    lv_obj_t *button_label = lv_label_create(button);
    lv_label_set_text(button_label, "Prøv nattilstand");
    lv_obj_set_style_text_font(button_label, &watch_font_danish_20, 0);
    lv_obj_center(button_label);

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

    _value = _night_value = nullptr;
    bsp_display_brightness_set(bsp_display_backlight_level_get());    // In case a night preview was cut off

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
    save(NVS_BRIGHTNESS, lv_slider_get_value(static_cast<lv_obj_t *>(lv_event_get_target(e))));
}

void Settings::onNightBrightnessChanged(lv_event_t *e)
{
    // A preview of the night brightness while dragging (the screen is only that dim with the night clock)
    Settings *app = static_cast<Settings *>(lv_event_get_user_data(e));
    night_brightness = lv_slider_get_value(static_cast<lv_obj_t *>(lv_event_get_target(e)));
    bsp_display_brightness_set(night_brightness);
    if (app->_night_value != nullptr) {
        lv_label_set_text_fmt(app->_night_value, "%d %%", night_brightness);
    }
}

void Settings::onNightBrightnessReleased(lv_event_t *e)
{
    night_brightness = lv_slider_get_value(static_cast<lv_obj_t *>(lv_event_get_target(e)));
    save(NVS_NIGHT_BRIGHTNESS, night_brightness);
    bsp_display_brightness_set(bsp_display_backlight_level_get());   // Back to the normal brightness
}

ESP_UTILS_REGISTER_PLUGIN_WITH_CONSTRUCTOR(systems::base::App, Settings, APP_NAME, []()
{
    return std::shared_ptr<Settings>(Settings::requestInstance(), [](Settings * p) {});
})

} // namespace esp_brookesia::apps
