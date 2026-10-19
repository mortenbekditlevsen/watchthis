/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include "lvgl.h"
#include "systems/phone/esp_brookesia_phone_app.hpp"

namespace esp_brookesia::apps {

/**
 * @brief "Musik": plays the MP3s uploaded via Synk (components/music_player). Playback continues in the background
 *        when the app is closed; this is only its remote control and track list.
 */
class Music: public systems::phone::App {
public:
    static Music *requestInstance();

    ~Music();

protected:
    Music();

    bool run(void) override;
    bool back(void) override;
    bool close(void) override;

private:
    static void onTimer(lv_timer_t *timer);
    static void onTrackClicked(lv_event_t *e);
    static void onPlayClicked(lv_event_t *e);
    static void onPrevClicked(lv_event_t *e);
    static void onNextClicked(lv_event_t *e);
    static void onVolumeChanged(lv_event_t *e);

    lv_obj_t *createButton(lv_obj_t *parent, const char *symbol, int32_t size, lv_event_cb_t cb);
    void buildList(void);
    void update(void);

    static Music *_instance;

    lv_obj_t *_title = nullptr;
    lv_obj_t *_time = nullptr;
    lv_obj_t *_play_label = nullptr;
    lv_obj_t *_volume = nullptr;
    lv_obj_t *_list = nullptr;
    int _highlighted = -1;
};

} // namespace esp_brookesia::apps
