/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include "music_player.h"
#include "watch_fonts.h"
#include "lvgl.h"
#include "esp_brookesia.hpp"
#ifdef ESP_UTILS_LOG_TAG
#   undef ESP_UTILS_LOG_TAG
#endif
#define ESP_UTILS_LOG_TAG "BS:Music"
#include "esp_lib_utils.h"
#include "esp_brookesia_app_music.hpp"

#define APP_NAME "Musik"

constexpr uint32_t UPDATE_MS = 500;
constexpr uint32_t ACCENT_COLOR = 0xF0588C;    // Same pink as the launcher icon
constexpr uint32_t BUTTON_COLOR = 0x2A2A2A;
constexpr int32_t SCREEN_W = 410;
constexpr int32_t CONTENT_W = 370;

using namespace esp_brookesia::systems;

LV_IMG_DECLARE(esp_brookesia_app_icon_launcher_music_112_112);

namespace esp_brookesia::apps {

Music *Music::_instance = nullptr;

Music *Music::requestInstance()
{
    if (_instance == nullptr) {
        _instance = new Music();
    }
    return _instance;
}

Music::Music():
    App(APP_NAME, &esp_brookesia_app_icon_launcher_music_112_112, true, false, false)
{
}

Music::~Music()
{
}

lv_obj_t *Music::createButton(lv_obj_t *parent, const char *symbol, int32_t size, lv_event_cb_t cb)
{
    lv_obj_t *button = lv_button_create(parent);
    lv_obj_set_size(button, size, size);
    lv_obj_set_style_radius(button, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(button, lv_color_hex(BUTTON_COLOR), 0);
    lv_obj_set_style_shadow_width(button, 0, 0);
    lv_obj_add_event_cb(button, cb, LV_EVENT_CLICKED, this);

    lv_obj_t *label = lv_label_create(button);
    lv_label_set_text(label, symbol);
    lv_obj_set_style_text_font(label, (size > 80) ? &lv_font_montserrat_36 : &lv_font_montserrat_28, 0);
    lv_obj_set_style_text_color(label, lv_color_white(), 0);
    lv_obj_center(label);
    return button;
}

bool Music::run(void)
{
    ESP_UTILS_LOGD("Run");

    // Everything created here is recorded by the core and cleaned up when the app closes (playback continues)
    lv_obj_t *screen = lv_screen_active();
    lv_obj_set_style_bg_color(screen, lv_color_black(), 0);
    lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);
    lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE);

    _title = lv_label_create(screen);
    lv_obj_set_width(_title, CONTENT_W);
    lv_label_set_long_mode(_title, LV_LABEL_LONG_DOT);
    lv_obj_set_style_text_align(_title, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_text_font(_title, &watch_font_danish_28, 0);
    lv_obj_set_style_text_color(_title, lv_color_white(), 0);
    lv_obj_align(_title, LV_ALIGN_TOP_MID, 0, 36);

    _time = lv_label_create(screen);
    lv_obj_set_style_text_font(_time, &lv_font_montserrat_20, 0);
    lv_obj_set_style_text_color(_time, lv_color_hex(0x999999), 0);
    lv_obj_align(_time, LV_ALIGN_TOP_MID, 0, 76);

    // Prev / play-pause / next
    lv_obj_t *controls = lv_obj_create(screen);
    lv_obj_remove_style_all(controls);
    lv_obj_set_size(controls, SCREEN_W, 100);
    lv_obj_align(controls, LV_ALIGN_TOP_MID, 0, 108);
    lv_obj_set_flex_flow(controls, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(controls, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(controls, 28, 0);
    createButton(controls, LV_SYMBOL_PREV, 70, onPrevClicked);
    lv_obj_t *play = createButton(controls, LV_SYMBOL_PLAY, 96, onPlayClicked);
    lv_obj_set_style_bg_color(play, lv_color_hex(ACCENT_COLOR), 0);
    _play_label = lv_obj_get_child(play, 0);
    createButton(controls, LV_SYMBOL_NEXT, 70, onNextClicked);

    // Volume
    lv_obj_t *vol_icon = lv_label_create(screen);
    lv_label_set_text(vol_icon, LV_SYMBOL_VOLUME_MID);
    lv_obj_set_style_text_font(vol_icon, &lv_font_montserrat_20, 0);
    lv_obj_set_style_text_color(vol_icon, lv_color_hex(0x999999), 0);
    lv_obj_align(vol_icon, LV_ALIGN_TOP_LEFT, 32, 226);

    _volume = lv_slider_create(screen);
    lv_obj_set_size(_volume, 290, 12);
    lv_obj_align(_volume, LV_ALIGN_TOP_LEFT, 74, 231);
    lv_slider_set_range(_volume, 0, 100);
    lv_obj_set_style_bg_color(_volume, lv_color_hex(0x333333), LV_PART_MAIN);
    lv_obj_set_style_bg_color(_volume, lv_color_hex(ACCENT_COLOR), LV_PART_INDICATOR);
    lv_obj_set_style_bg_color(_volume, lv_color_white(), LV_PART_KNOB);
    lv_obj_add_event_cb(_volume, onVolumeChanged, LV_EVENT_VALUE_CHANGED, this);
    lv_obj_set_ext_click_area(_volume, 16);

    // Track list
    _list = lv_list_create(screen);
    lv_obj_set_size(_list, CONTENT_W, 210);
    lv_obj_align(_list, LV_ALIGN_TOP_MID, 0, 268);
    lv_obj_set_style_bg_opa(_list, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(_list, 0, 0);
    lv_obj_set_style_pad_all(_list, 0, 0);
    lv_obj_set_style_text_font(_list, &watch_font_danish_20, 0);

    music_player_refresh();
    buildList();

    music_player_status_t status;
    music_player_get_status(&status);
    lv_slider_set_value(_volume, status.volume, LV_ANIM_OFF);

    update();
    lv_timer_create(onTimer, UPDATE_MS, this);

    return true;
}

void Music::buildList(void)
{
    lv_obj_clean(_list);
    _highlighted = -1;

    music_player_status_t status;
    music_player_get_status(&status);
    if (status.count == 0) {
        lv_obj_t *empty = lv_label_create(_list);
        lv_obj_set_width(empty, CONTENT_W);
        lv_label_set_long_mode(empty, LV_LABEL_LONG_WRAP);
        lv_obj_set_style_text_align(empty, LV_TEXT_ALIGN_CENTER, 0);
        lv_obj_set_style_text_color(empty, lv_color_hex(0x888888), 0);
        lv_label_set_text(empty, "Ingen musik endnu.\nUpload MP3'er fra telefonen via Synk.");
        return;
    }

    char title[64];
    for (int i = 0; i < status.count; i++) {
        if (!music_player_track_title(i, title, sizeof(title))) {
            break;
        }
        lv_obj_t *button = lv_list_add_button(_list, LV_SYMBOL_AUDIO, title);
        lv_obj_set_style_bg_color(button, lv_color_hex(0x161616), 0);
        lv_obj_set_style_text_color(button, lv_color_white(), 0);
        lv_obj_set_style_border_side(button, LV_BORDER_SIDE_BOTTOM, 0);
        lv_obj_set_style_border_color(button, lv_color_hex(0x2A2A2A), 0);
        lv_obj_set_style_pad_ver(button, 14, 0);
        lv_obj_set_user_data(button, reinterpret_cast<void *>(static_cast<intptr_t>(i)));
        lv_obj_add_event_cb(button, onTrackClicked, LV_EVENT_CLICKED, this);
        lv_obj_t *label = lv_obj_get_child(button, 1);
        if (label != nullptr) {
            lv_label_set_long_mode(label, LV_LABEL_LONG_DOT);
        }
    }
}

void Music::update(void)
{
    music_player_status_t status;
    music_player_get_status(&status);

    if (status.count == 0) {
        lv_label_set_text(_title, "Musik");
        lv_label_set_text(_time, "");
    } else {
        lv_label_set_text(_title, status.title);
        if (status.state == MUSIC_PLAYER_STOPPED) {
            lv_label_set_text_fmt(_time, "%d / %d", status.index + 1, status.count);
        } else {
            lv_label_set_text_fmt(_time, "%u:%02u    %d / %d", (unsigned)(status.elapsed_s / 60),
                                  (unsigned)(status.elapsed_s % 60), status.index + 1, status.count);
        }
    }
    lv_label_set_text(_play_label, (status.state == MUSIC_PLAYER_PLAYING) ? LV_SYMBOL_PAUSE : LV_SYMBOL_PLAY);

    // Highlight the current track in the list
    if ((status.index != _highlighted) && (status.count > 0)) {
        const int32_t children = lv_obj_get_child_count(_list);
        for (int32_t i = 0; i < children; i++) {
            lv_obj_t *button = lv_obj_get_child(_list, i);
            const bool current = (i == status.index);
            lv_obj_set_style_text_color(button, current ? lv_color_hex(ACCENT_COLOR) : lv_color_white(), 0);
            if (current) {
                lv_obj_scroll_to_view(button, LV_ANIM_ON);
            }
        }
        _highlighted = status.index;
    }
}

bool Music::back(void)
{
    ESP_UTILS_LOGD("Back");

    ESP_UTILS_CHECK_FALSE_RETURN(notifyCoreClosed(), false, "Notify core closed failed");

    return true;
}

bool Music::close(void)
{
    ESP_UTILS_LOGD("Close");

    // The core deletes the recorded timer and objects itself; the music keeps playing
    _title = _time = _play_label = _volume = _list = nullptr;
    _highlighted = -1;

    return true;
}

void Music::onTimer(lv_timer_t *timer)
{
    Music *app = static_cast<Music *>(lv_timer_get_user_data(timer));
    if (app->_title != nullptr) {
        app->update();
    }
}

void Music::onTrackClicked(lv_event_t *e)
{
    lv_obj_t *button = static_cast<lv_obj_t *>(lv_event_get_current_target(e));
    music_player_play(static_cast<int>(reinterpret_cast<intptr_t>(lv_obj_get_user_data(button))));
}

void Music::onPlayClicked(lv_event_t *e)
{
    music_player_toggle();
}

void Music::onPrevClicked(lv_event_t *e)
{
    music_player_prev();
}

void Music::onNextClicked(lv_event_t *e)
{
    music_player_next();
}

void Music::onVolumeChanged(lv_event_t *e)
{
    lv_obj_t *slider = static_cast<lv_obj_t *>(lv_event_get_target(e));
    music_player_set_volume(lv_slider_get_value(slider));
}

ESP_UTILS_REGISTER_PLUGIN_WITH_CONSTRUCTOR(systems::base::App, Music, APP_NAME, []()
{
    return std::shared_ptr<Music>(Music::requestInstance(), [](Music * p) {});
})

} // namespace esp_brookesia::apps
