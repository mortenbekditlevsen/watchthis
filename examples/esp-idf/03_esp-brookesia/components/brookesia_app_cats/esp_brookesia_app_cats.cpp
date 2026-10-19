/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include <cstring>
#include <string>
#include <vector>
#include "file_store.h"
#include "lvgl.h"
#include "esp_brookesia.hpp"
#ifdef ESP_UTILS_LOG_TAG
#   undef ESP_UTILS_LOG_TAG
#endif
#define ESP_UTILS_LOG_TAG "BS:Cats"
#include "esp_lib_utils.h"
#include "cats_jpeg_decoder.hpp"
#include "esp_brookesia_app_cats.hpp"

#define APP_NAME "Katte"

constexpr int MAX_PHOTOS = 512;

// Same touch classification as the Little Game: below TAP_MAX_MOVE is a tap, above SWIPE_MIN_MOVE a swipe
constexpr int32_t TAP_MAX_MOVE = 15;
constexpr int32_t SWIPE_MIN_MOVE = 40;

using namespace esp_brookesia::systems;

LV_IMG_DECLARE(esp_brookesia_app_icon_launcher_cats_112_112);

namespace {

// Ids of the photos in the file store, reloaded each time the app opens (uploads/deletes happen in between)
std::vector<std::string> photo_ids;

void load_photo_ids(void)
{
    photo_ids.clear();
    std::vector<file_store_entry_t> entries(MAX_PHOTOS);
    const int count = file_store_list(FILE_STORE_PHOTO, entries.data(), MAX_PHOTOS);
    for (int i = 0; i < LV_MIN(count, MAX_PHOTOS); i++) {
        photo_ids.emplace_back(entries[i].id);
    }
    ESP_UTILS_LOGI("%d photos", (int)photo_ids.size());
}

} // namespace

namespace esp_brookesia::apps {

Cats *Cats::_instance = nullptr;

Cats *Cats::requestInstance()
{
    if (_instance == nullptr) {
        _instance = new Cats();
    }
    return _instance;
}

Cats::Cats():
    App(APP_NAME, &esp_brookesia_app_icon_launcher_cats_112_112, true, false, false)
{
}

Cats::~Cats()
{
}

bool Cats::run(void)
{
    ESP_UTILS_LOGD("Run");

    // Everything created here is recorded by the core and cleaned up when the app closes
    lv_obj_t *screen = lv_screen_active();
    lv_obj_set_style_bg_color(screen, lv_color_black(), 0);
    lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);
    lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_event_cb(screen, onScreenEvent, LV_EVENT_PRESSED, this);
    lv_obj_add_event_cb(screen, onScreenEvent, LV_EVENT_RELEASED, this);

    cats_jpeg_decoder_init();
    load_photo_ids();
    if (photo_ids.empty()) {
        lv_obj_t *label = lv_label_create(screen);
        lv_label_set_text(label, "Ingen billeder");
        lv_obj_set_style_text_color(label, lv_color_white(), 0);
        lv_obj_center(label);
        return true;
    }

    _image = lv_image_create(screen);
    lv_obj_remove_flag(_image, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_center(_image);

    _counter = lv_label_create(screen);
    lv_obj_set_style_text_font(_counter, &lv_font_montserrat_18, 0);
    lv_obj_set_style_text_color(_counter, lv_color_white(), 0);
    lv_obj_set_style_bg_color(_counter, lv_color_black(), 0);
    lv_obj_set_style_bg_opa(_counter, LV_OPA_60, 0);
    lv_obj_set_style_radius(_counter, 12, 0);
    lv_obj_set_style_pad_hor(_counter, 12, 0);
    lv_obj_set_style_pad_ver(_counter, 4, 0);
    lv_obj_align(_counter, LV_ALIGN_BOTTOM_MID, 0, -24);
    lv_obj_add_flag(_counter, LV_OBJ_FLAG_HIDDEN);

    // Reopen on the photo shown last time, if it still exists
    int index = 0;
    for (size_t i = 0; i < photo_ids.size(); i++) {
        if (photo_ids[i] == _current_id) {
            index = i;
            break;
        }
    }
    showImage(index);

    return true;
}

bool Cats::back(void)
{
    ESP_UTILS_LOGD("Back");

    ESP_UTILS_CHECK_FALSE_RETURN(notifyCoreClosed(), false, "Notify core closed failed");

    return true;
}

bool Cats::close(void)
{
    ESP_UTILS_LOGD("Close");

    cats_jpeg_decoder_release();

    // The core deletes the recorded objects itself
    _image = nullptr;
    _counter = nullptr;

    return true;
}

void Cats::showImage(int index)
{
    const int count = photo_ids.size();
    if ((_image == nullptr) || (count == 0)) {
        return;
    }

    _index = ((index % count) + count) % count;
    _current_id = photo_ids[_index];

    char path[FILE_STORE_PATH_MAX];
    if (!file_store_path(FILE_STORE_PHOTO, _current_id.c_str(), path, sizeof(path))) {
        return;
    }
    lv_image_dsc_t &dsc = _dsc[_dsc_next];
    _dsc_next ^= 1;
    cats_jpeg_decoder_make_src(&dsc, path);
    lv_image_set_src(_image, &dsc);

    lv_label_set_text_fmt(_counter, "%d / %d", _index + 1, count);
}

void Cats::onScreenEvent(lv_event_t *e)
{
    Cats *app = static_cast<Cats *>(lv_event_get_user_data(e));
    lv_indev_t *indev = lv_indev_active();
    if ((indev == nullptr) || (app->_image == nullptr)) {
        return;
    }

    lv_point_t point;
    lv_indev_get_point(indev, &point);

    if (lv_event_get_code(e) == LV_EVENT_PRESSED) {
        app->_press_point = point;
        return;
    }

    const int32_t dx = point.x - app->_press_point.x;
    const int32_t dy = point.y - app->_press_point.y;
    const int32_t move = LV_MAX(LV_ABS(dx), LV_ABS(dy));

    if (move < TAP_MAX_MOVE) {
        if (lv_obj_has_flag(app->_counter, LV_OBJ_FLAG_HIDDEN)) {
            lv_obj_remove_flag(app->_counter, LV_OBJ_FLAG_HIDDEN);
        } else {
            lv_obj_add_flag(app->_counter, LV_OBJ_FLAG_HIDDEN);
        }
    } else if ((move >= SWIPE_MIN_MOVE) && (LV_ABS(dx) > LV_ABS(dy))) {
        // Swipe left = next photo, like turning a page
        app->showImage(app->_index + ((dx < 0) ? 1 : -1));
    }
}

ESP_UTILS_REGISTER_PLUGIN_WITH_CONSTRUCTOR(systems::base::App, Cats, APP_NAME, []()
{
    return std::shared_ptr<Cats>(Cats::requestInstance(), [](Cats * p) {});
})

} // namespace esp_brookesia::apps
