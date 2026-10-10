/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include "lvgl.h"
#include "systems/phone/esp_brookesia_phone_app.hpp"

namespace esp_brookesia::apps {

/**
 * @brief Full-screen particle effects (starfield, sphere, spirograph, cube), simulated in Embedded Swift
 *        (components/particle_effects) and drawn here with LVGL.
 */
class Particles: public systems::phone::App {
public:
    static Particles *requestInstance();

    ~Particles();

protected:
    Particles();

    bool run(void) override;
    bool back(void) override;
    bool close(void) override;
    bool pause(void) override;
    bool resume(void) override;

private:
    static void onTick(lv_timer_t *timer);
    static void onDraw(lv_event_t *e);

    static Particles *_instance;

    lv_obj_t *_canvas = nullptr;
    lv_timer_t *_timer = nullptr;
    bool _needs_reset = true;
};

} // namespace esp_brookesia::apps
