/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include "lvgl.h"
#include "systems/phone/esp_brookesia_phone_app.hpp"

namespace esp_brookesia::apps {

/**
 * @brief "Skridt": today's steps (from the IMU's pedometer, components/step_counter) with progress towards a daily
 *        goal, and yesterday's total.
 */
class Steps: public systems::phone::App {
public:
    static Steps *requestInstance();

    ~Steps();

protected:
    Steps();

    bool run(void) override;
    bool back(void) override;
    bool close(void) override;

private:
    static void onTimer(lv_timer_t *timer);

    void update(void);

    static Steps *_instance;

    lv_obj_t *_arc = nullptr;
    lv_obj_t *_today = nullptr;
    lv_obj_t *_yesterday = nullptr;
};

} // namespace esp_brookesia::apps
