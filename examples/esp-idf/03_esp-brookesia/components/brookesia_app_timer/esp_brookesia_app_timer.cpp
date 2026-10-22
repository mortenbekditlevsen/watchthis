/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include "lvgl.h"
#include "esp_brookesia.hpp"
#ifdef ESP_UTILS_LOG_TAG
#   undef ESP_UTILS_LOG_TAG
#endif
#define ESP_UTILS_LOG_TAG "BS:Timer"
#include "esp_lib_utils.h"
#include "watch_tools.h"
#include "esp_brookesia_app_timer.hpp"

#define APP_NAME "Timer"

using namespace esp_brookesia::systems;

LV_IMG_DECLARE(esp_brookesia_app_icon_launcher_timer_112_112);

namespace esp_brookesia::apps {

Timer *Timer::_instance = nullptr;

Timer *Timer::requestInstance()
{
    if (_instance == nullptr) {
        _instance = new Timer();
    }
    return _instance;
}

Timer::Timer():
    App(APP_NAME, &esp_brookesia_app_icon_launcher_timer_112_112, true, false, false)
{
}

Timer::~Timer()
{
}

bool Timer::run(void)
{
    ESP_UTILS_LOGD("Run");

    // The UI is Swift (components/watch_tools); its objects and timer are recorded by the core and cleaned up when
    // the app closes
    timer_app_show(lv_screen_active());

    return true;
}

bool Timer::back(void)
{
    ESP_UTILS_LOGD("Back");

    ESP_UTILS_CHECK_FALSE_RETURN(notifyCoreClosed(), false, "Notify core closed failed");

    return true;
}

bool Timer::close(void)
{
    ESP_UTILS_LOGD("Close");

    timer_app_hide();

    return true;
}

ESP_UTILS_REGISTER_PLUGIN_WITH_CONSTRUCTOR(systems::base::App, Timer, APP_NAME, []()
{
    return std::shared_ptr<Timer>(Timer::requestInstance(), [](Timer * p) {});
})

} // namespace esp_brookesia::apps
