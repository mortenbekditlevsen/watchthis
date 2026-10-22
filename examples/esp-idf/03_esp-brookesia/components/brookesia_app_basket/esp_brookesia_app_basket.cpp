/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include "lvgl.h"
#include "esp_brookesia.hpp"
#ifdef ESP_UTILS_LOG_TAG
#   undef ESP_UTILS_LOG_TAG
#endif
#define ESP_UTILS_LOG_TAG "BS:Basket"
#include "esp_lib_utils.h"
#include "watch_faces.h"
#include "esp_brookesia_app_basket.hpp"

#define APP_NAME "Basket"

using namespace esp_brookesia::systems;

LV_IMG_DECLARE(esp_brookesia_app_icon_launcher_basket_112_112);

namespace esp_brookesia::apps {

Basket *Basket::_instance = nullptr;

Basket *Basket::requestInstance()
{
    if (_instance == nullptr) {
        _instance = new Basket();
    }
    return _instance;
}

// No navigation gestures (nor the bar at the bottom that shows them): throwing the ball from low on the screen
// would swipe home. The power key goes back.
static phone::App::Config phone_config()
{
    phone::App::Config config =
        phone::App::Config::SIMPLE_CONSTRUCTOR(&esp_brookesia_app_icon_launcher_basket_112_112, false, false);
    config.flags.enable_navigation_gesture = 0;
    return config;
}

Basket::Basket():
    App(base::App::Config::SIMPLE_CONSTRUCTOR(APP_NAME, &esp_brookesia_app_icon_launcher_basket_112_112, true),
        phone_config())
{
}

Basket::~Basket()
{
}

bool Basket::run(void)
{
    ESP_UTILS_LOGD("Run");

    // The UI is Swift (components/watch_faces); its objects are recorded by the core and cleaned up when
    // the app closes
    basket_app_show(lv_screen_active());

    return true;
}

bool Basket::back(void)
{
    ESP_UTILS_LOGD("Back");

    ESP_UTILS_CHECK_FALSE_RETURN(notifyCoreClosed(), false, "Notify core closed failed");

    return true;
}

bool Basket::close(void)
{
    ESP_UTILS_LOGD("Close");

    basket_app_hide();

    return true;
}

ESP_UTILS_REGISTER_PLUGIN_WITH_CONSTRUCTOR(systems::base::App, Basket, APP_NAME, []()
{
    return std::shared_ptr<Basket>(Basket::requestInstance(), [](Basket * p) {});
})

} // namespace esp_brookesia::apps
