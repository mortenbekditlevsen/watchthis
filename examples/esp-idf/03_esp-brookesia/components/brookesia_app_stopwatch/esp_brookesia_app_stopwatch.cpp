/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include "lvgl.h"
#include "esp_brookesia.hpp"
#ifdef ESP_UTILS_LOG_TAG
#   undef ESP_UTILS_LOG_TAG
#endif
#define ESP_UTILS_LOG_TAG "BS:Stopwatch"
#include "esp_lib_utils.h"
#include "watch_tools.h"
#include "esp_brookesia_app_stopwatch.hpp"

#define APP_NAME "Stopur"

using namespace esp_brookesia::systems;

LV_IMG_DECLARE(esp_brookesia_app_icon_launcher_stopwatch_112_112);

namespace esp_brookesia::apps {

Stopwatch *Stopwatch::_instance = nullptr;

Stopwatch *Stopwatch::requestInstance()
{
    if (_instance == nullptr) {
        _instance = new Stopwatch();
    }
    return _instance;
}

Stopwatch::Stopwatch():
    App(APP_NAME, &esp_brookesia_app_icon_launcher_stopwatch_112_112, true, false, false)
{
}

Stopwatch::~Stopwatch()
{
}

bool Stopwatch::run(void)
{
    ESP_UTILS_LOGD("Run");

    // The UI is Swift (components/watch_tools); its objects and timer are recorded by the core and cleaned up when
    // the app closes
    stopwatch_app_show(lv_screen_active());

    return true;
}

bool Stopwatch::back(void)
{
    ESP_UTILS_LOGD("Back");

    ESP_UTILS_CHECK_FALSE_RETURN(notifyCoreClosed(), false, "Notify core closed failed");

    return true;
}

bool Stopwatch::close(void)
{
    ESP_UTILS_LOGD("Close");

    stopwatch_app_hide();

    return true;
}

ESP_UTILS_REGISTER_PLUGIN_WITH_CONSTRUCTOR(systems::base::App, Stopwatch, APP_NAME, []()
{
    return std::shared_ptr<Stopwatch>(Stopwatch::requestInstance(), [](Stopwatch * p) {});
})

} // namespace esp_brookesia::apps
