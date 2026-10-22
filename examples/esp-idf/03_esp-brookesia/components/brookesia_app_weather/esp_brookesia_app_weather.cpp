/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include "lvgl.h"
#include "esp_brookesia.hpp"
#ifdef ESP_UTILS_LOG_TAG
#   undef ESP_UTILS_LOG_TAG
#endif
#define ESP_UTILS_LOG_TAG "BS:Weather"
#include "esp_lib_utils.h"
#include "watch_faces.h"
#include "esp_brookesia_app_weather.hpp"

#define APP_NAME "Vejr"

using namespace esp_brookesia::systems;

LV_IMG_DECLARE(esp_brookesia_app_icon_launcher_weather_112_112);

namespace esp_brookesia::apps {

Weather *Weather::_instance = nullptr;

Weather *Weather::requestInstance()
{
    if (_instance == nullptr) {
        _instance = new Weather();
    }
    return _instance;
}

Weather::Weather():
    App(APP_NAME, &esp_brookesia_app_icon_launcher_weather_112_112, true, false, false)
{
}

Weather::~Weather()
{
}

bool Weather::run(void)
{
    ESP_UTILS_LOGD("Run");

    // The UI is Swift (components/watch_faces); its objects are recorded by the core and cleaned up when
    // the app closes
    weather_app_show(lv_screen_active());

    return true;
}

bool Weather::back(void)
{
    ESP_UTILS_LOGD("Back");

    ESP_UTILS_CHECK_FALSE_RETURN(notifyCoreClosed(), false, "Notify core closed failed");

    return true;
}

bool Weather::close(void)
{
    ESP_UTILS_LOGD("Close");

    weather_app_hide();

    return true;
}

ESP_UTILS_REGISTER_PLUGIN_WITH_CONSTRUCTOR(systems::base::App, Weather, APP_NAME, []()
{
    return std::shared_ptr<Weather>(Weather::requestInstance(), [](Weather * p) {});
})

} // namespace esp_brookesia::apps
