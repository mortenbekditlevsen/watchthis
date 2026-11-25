/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include "lvgl.h"
#include "esp_brookesia.hpp"
#ifdef ESP_UTILS_LOG_TAG
#   undef ESP_UTILS_LOG_TAG
#endif
#define ESP_UTILS_LOG_TAG "BS:Advent"
#include "esp_lib_utils.h"
#include "watch_faces.h"
#include "esp_brookesia_app_advent.hpp"

#define APP_NAME "Julekalender"

using namespace esp_brookesia::systems;

LV_IMG_DECLARE(esp_brookesia_app_icon_launcher_advent_112_112);

namespace esp_brookesia::apps {

Advent *Advent::_instance = nullptr;

Advent *Advent::requestInstance()
{
    if (_instance == nullptr) {
        _instance = new Advent();
    }
    return _instance;
}

// No navigation gestures (nor the home indicator at the bottom that shows them); the app has its own way back from a
// door, and the power key goes back
static phone::App::Config phone_config()
{
    phone::App::Config config =
        phone::App::Config::SIMPLE_CONSTRUCTOR(&esp_brookesia_app_icon_launcher_advent_112_112, false, false);
    config.flags.enable_navigation_gesture = 0;
    return config;
}

Advent::Advent():
    App(base::App::Config::SIMPLE_CONSTRUCTOR(APP_NAME, &esp_brookesia_app_icon_launcher_advent_112_112, true),
        phone_config())
{
}

Advent::~Advent()
{
}

// The app itself is Swift (components/watch_faces/AdventApp.swift); its objects are recorded by the core and cleaned
// up when the app closes
bool Advent::run(void)
{
    advent_app_show(lv_screen_active());
    return true;
}

bool Advent::back(void)
{
    // From an open door back to the calendar; from the calendar, close
    if (!advent_app_back()) {
        ESP_UTILS_CHECK_FALSE_RETURN(notifyCoreClosed(), false, "Notify core closed failed");
    }
    return true;
}

bool Advent::close(void)
{
    advent_app_hide();
    return true;
}

ESP_UTILS_REGISTER_PLUGIN_WITH_CONSTRUCTOR(systems::base::App, Advent, APP_NAME, []()
{
    return std::shared_ptr<Advent>(Advent::requestInstance(), [](Advent * p) {});
})

} // namespace esp_brookesia::apps
