/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include <string>
#include "lvgl.h"
#include "systems/phone/esp_brookesia_phone_app.hpp"

namespace esp_brookesia::apps {

/**
 * @brief Full-screen photo browser for the JPEGs in the file store (components/file_store; preloaded with the
 *        cats in images/), decoded while drawing by cats_jpeg_decoder. Swipe left/right to browse, tap to show/hide
 *        the position.
 */
class Cats: public systems::phone::App {
public:
    static Cats *requestInstance();

    ~Cats();

protected:
    Cats();

    bool run(void) override;
    bool back(void) override;
    bool close(void) override;

private:
    static void onScreenEvent(lv_event_t *e);

    void showImage(int index);

    static Cats *_instance;

    lv_obj_t *_image = nullptr;
    lv_obj_t *_counter = nullptr;
    lv_image_dsc_t _dsc[2] = {};    // Alternated, so a new image never reuses the descriptor currently shown
    int _dsc_next = 0;
    int _index = 0;
    std::string _current_id;        // Photo shown, kept across app opens
    lv_point_t _press_point = {};
};

} // namespace esp_brookesia::apps
