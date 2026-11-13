/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include "lvgl.h"
#include "esp_brookesia.hpp"
#ifdef ESP_UTILS_LOG_TAG
#   undef ESP_UTILS_LOG_TAG
#endif
#define ESP_UTILS_LOG_TAG "BS:Paint"
#include "esp_lib_utils.h"
#include "watch_faces.h"
#include "esp_brookesia_app_paint.hpp"

#define APP_NAME "Tegn"

using namespace esp_brookesia::systems;

LV_IMG_DECLARE(esp_brookesia_app_icon_launcher_paint_112_112);

namespace esp_brookesia::apps {

Paint *Paint::_instance = nullptr;

Paint *Paint::requestInstance()
{
    if (_instance == nullptr) {
        _instance = new Paint();
    }
    return _instance;
}

// No navigation gestures (nor the bar at the bottom that shows them): drawing reaches the edges, and the bottom is
// close to the edge where a swipe up (home) starts. The power key goes back.
static phone::App::Config phone_config()
{
    phone::App::Config config =
        phone::App::Config::SIMPLE_CONSTRUCTOR(&esp_brookesia_app_icon_launcher_paint_112_112, false, false);
    config.flags.enable_navigation_gesture = 0;
    return config;
}

Paint::Paint():
    App(base::App::Config::SIMPLE_CONSTRUCTOR(APP_NAME, &esp_brookesia_app_icon_launcher_paint_112_112, true),
        phone_config())
{
}

Paint::~Paint()
{
}

bool Paint::run(void)
{
    ESP_UTILS_LOGD("Run");

    // The UI is Swift (components/watch_faces); its objects are recorded by the core and cleaned up when
    // the app closes
    paint_app_show(lv_screen_active());

    return true;
}

bool Paint::back(void)
{
    ESP_UTILS_LOGD("Back");

    ESP_UTILS_CHECK_FALSE_RETURN(notifyCoreClosed(), false, "Notify core closed failed");

    return true;
}

bool Paint::close(void)
{
    ESP_UTILS_LOGD("Close");

    paint_app_hide();

    return true;
}

ESP_UTILS_REGISTER_PLUGIN_WITH_CONSTRUCTOR(systems::base::App, Paint, APP_NAME, []()
{
    return std::shared_ptr<Paint>(Paint::requestInstance(), [](Paint * p) {});
})

} // namespace esp_brookesia::apps
