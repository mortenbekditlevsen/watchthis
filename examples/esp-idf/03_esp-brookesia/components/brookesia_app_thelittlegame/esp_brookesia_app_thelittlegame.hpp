/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include "lvgl.h"
#include "systems/phone/esp_brookesia_phone_app.hpp"
#include "thelittlegame.h"

namespace esp_brookesia::apps {

/**
 * @brief thelittlegame (Embedded Swift, components/thelittlegame) with its 10x6 LED matrix drawn as scaled-up LVGL
 *        pixels. Swipes are the direction buttons, a tap is "fire" and the BOOT button is "select".
 */
class TheLittleGame: public systems::phone::App {
public:
    static TheLittleGame *requestInstance();

    ~TheLittleGame();

protected:
    TheLittleGame();

    bool run(void) override;
    bool back(void) override;
    bool close(void) override;
    bool pause(void) override;
    bool resume(void) override;

private:
    static constexpr int PIXEL_COUNT = LITTLEGAME_WIDTH * LITTLEGAME_HEIGHT;

    static void onTick(lv_timer_t *timer);
    static void onScreenEvent(lv_event_t *e);

    static TheLittleGame *_instance;

    lv_obj_t *_pixels[PIXEL_COUNT] = {};
    lv_timer_t *_timer = nullptr;
    uint8_t _rgb[PIXEL_COUNT * 3] = {};
    // Last values pushed to LVGL, so only changed pixels get restyled and redrawn
    uint32_t _shown_rgb[PIXEL_COUNT] = {};
    int _boot_level = 1;
    lv_point_t _press_point = {};
};

} // namespace esp_brookesia::apps
