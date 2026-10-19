/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include <cstring>
#include <mutex>
#include <string>
#include "ble_sync.h"
#include "music_player.h"
#include "file_store.h"
#include "watch_fonts.h"
#include "lvgl.h"
#include "esp_brookesia.hpp"
#ifdef ESP_UTILS_LOG_TAG
#   undef ESP_UTILS_LOG_TAG
#endif
#define ESP_UTILS_LOG_TAG "BS:Sync"
#include "esp_lib_utils.h"
#include "esp_brookesia_app_sync.hpp"

#define APP_NAME "Synk"

constexpr uint32_t UI_TIMER_MS = 200;
constexpr uint32_t BLE_TICK_EVERY = 1000 / UI_TIMER_MS;   // ble_sync_tick() about once a second
constexpr int32_t QR_SIZE = 220;
constexpr uint32_t MUSIC_STOP_TIMEOUT_MS = 2000;

using namespace esp_brookesia::systems;

LV_IMG_DECLARE(esp_brookesia_app_icon_launcher_sync_112_112);

namespace {

// Latest BLE status. Written by the status callback (BLE host task or the LVGL task), read by the UI timer.
struct Status {
    std::mutex mutex;
    ble_sync_state_t state = BLE_SYNC_STATE_OFF;
    std::string qr_payload;
    bool dirty = true;
};
Status status;

void on_ble_status(ble_sync_state_t state, const char *qr_payload)
{
    // Must not block or take the LVGL lock (see ble_sync.h): just copy
    std::lock_guard<std::mutex> lock(status.mutex);
    status.state = state;
    status.qr_payload = (qr_payload != nullptr) ? qr_payload : "";
    status.dirty = true;
}

const char *state_text(ble_sync_state_t state)
{
    switch (state) {
    case BLE_SYNC_STATE_STARTING:
        return "Starter Bluetooth...";
    case BLE_SYNC_STATE_ADVERTISING:
        return "Venter på telefonen";
    case BLE_SYNC_STATE_PAIRING:
        return "Scan koden med appen på telefonen";
    case BLE_SYNC_STATE_CONNECTED:
        return "Telefon forbundet...";
    case BLE_SYNC_STATE_SESSION:
        return "Forbundet med telefonen";
    case BLE_SYNC_STATE_ERROR:
        return "Bluetooth kunne ikke starte";
    default:
        return "";
    }
}

// The proof-of-possession code from the QR payload ({"...","pop":"7K2M9XAB"}), shown as a typing fallback
std::string pop_from_payload(const std::string &payload)
{
    const std::string key = "\"pop\":\"";
    const size_t start = payload.find(key);
    if (start == std::string::npos) {
        return "";
    }
    const size_t end = payload.find('"', start + key.size());
    std::string pop = payload.substr(start + key.size(), end - start - key.size());
    if (pop.size() == 8) {
        pop.insert(4, " ");     // Easier to read: 7K2M 9XAB
    }
    return pop;
}

} // namespace

namespace esp_brookesia::apps {

Sync *Sync::_instance = nullptr;

Sync *Sync::requestInstance()
{
    if (_instance == nullptr) {
        _instance = new Sync();
    }
    return _instance;
}

Sync::Sync():
    App(APP_NAME, &esp_brookesia_app_icon_launcher_sync_112_112, true, false, false)
{
}

Sync::~Sync()
{
}

bool Sync::run(void)
{
    ESP_UTILS_LOGD("Run");

    // Everything created here is recorded by the core and cleaned up when the app closes
    lv_obj_t *screen = lv_screen_active();
    lv_obj_set_style_bg_color(screen, lv_color_black(), 0);
    lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);
    lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t *title = lv_label_create(screen);
    lv_label_set_text(title, "Synk");
    lv_obj_set_style_text_font(title, &lv_font_montserrat_28, 0);
    lv_obj_set_style_text_color(title, lv_color_white(), 0);
    lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 24);

    _status = lv_label_create(screen);
    lv_obj_set_width(_status, lv_pct(90));
    lv_label_set_long_mode(_status, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_align(_status, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_text_font(_status, &watch_font_danish_20, 0);
    lv_obj_set_style_text_color(_status, lv_color_hex(0xCCCCCC), 0);
    lv_obj_align(_status, LV_ALIGN_TOP_MID, 0, 70);

    // QR code on a white quiet zone, so phones can scan it off the black screen
    _qr = lv_qrcode_create(screen);
    lv_qrcode_set_size(_qr, QR_SIZE);
    lv_qrcode_set_dark_color(_qr, lv_color_black());
    lv_qrcode_set_light_color(_qr, lv_color_white());
    lv_obj_set_style_border_color(_qr, lv_color_white(), 0);
    lv_obj_set_style_border_width(_qr, 10, 0);
    lv_obj_align(_qr, LV_ALIGN_TOP_MID, 0, 130);
    lv_obj_add_flag(_qr, LV_OBJ_FLAG_HIDDEN);

    _pop = lv_label_create(screen);
    lv_obj_set_style_text_font(_pop, &lv_font_montserrat_24, 0);
    lv_obj_set_style_text_color(_pop, lv_color_white(), 0);
    lv_obj_align(_pop, LV_ALIGN_TOP_MID, 0, 130 + QR_SIZE + 2 * 10 + 8);
    lv_obj_add_flag(_pop, LV_OBJ_FLAG_HIDDEN);

    _storage = lv_label_create(screen);
    lv_obj_set_style_text_font(_storage, &lv_font_montserrat_16, 0);
    lv_obj_set_style_text_color(_storage, lv_color_hex(0x888888), 0);
    lv_obj_align(_storage, LV_ALIGN_CENTER, 0, 20);

    _reset_button = lv_button_create(screen);
    lv_obj_set_style_bg_color(_reset_button, lv_color_hex(0x333333), 0);
    lv_obj_align(_reset_button, LV_ALIGN_BOTTOM_MID, 0, -40);
    lv_obj_add_event_cb(_reset_button, onResetPairing, LV_EVENT_CLICKED, this);
    lv_obj_t *reset_label = lv_label_create(_reset_button);
    lv_label_set_text(reset_label, "Par ny telefon");
    lv_obj_set_style_text_font(reset_label, &watch_font_danish_20, 0);
    lv_obj_center(reset_label);

    updateStorageInfo();
    _ticks = 0;
    lv_timer_create(onTimer, UI_TIMER_MS, this);
    startBle();

    return true;
}

bool Sync::back(void)
{
    ESP_UTILS_LOGD("Back");

    ESP_UTILS_CHECK_FALSE_RETURN(notifyCoreClosed(), false, "Notify core closed failed");

    return true;
}

bool Sync::close(void)
{
    ESP_UTILS_LOGD("Close");

    stopBle();
    // The core deletes the recorded timer and objects itself
    _status = _qr = _pop = _storage = _reset_button = nullptr;

    return true;
}

bool Sync::pause(void)
{
    // BLE only runs while Synk is in the foreground
    stopBle();
    return true;
}

bool Sync::resume(void)
{
    startBle();
    return true;
}

void Sync::startBle(void)
{
    // BLE and the MP3 decoder don't both fit in RAM (with music paused, BLE was left with 8 KB and pairing failed)
    if (!music_player_stop_and_wait(MUSIC_STOP_TIMEOUT_MS)) {
        ESP_UTILS_LOGW("Music didn't stop in time");
    }
    ESP_UTILS_LOGI("Free internal heap before BLE: %u KB", (unsigned)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024));
    if (!ble_sync_start(on_ble_status)) {
        on_ble_status(BLE_SYNC_STATE_ERROR, nullptr);
    }
    ESP_UTILS_LOGI("Free internal heap with BLE: %u KB", (unsigned)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024));
}

void Sync::stopBle(void)
{
    // The status callback never takes the LVGL lock, so stopping (which waits for the BLE host task) from the LVGL
    // task can't deadlock
    ble_sync_stop();
    ESP_UTILS_LOGI("Free internal heap after BLE: %u KB", (unsigned)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024));
}

void Sync::updateStorageInfo(void)
{
    file_store_entry_t entry;
    const int photos = file_store_list(FILE_STORE_PHOTO, &entry, 0);
    const int music = file_store_list(FILE_STORE_MUSIC, &entry, 0);
    size_t total = 0, used = 0;
    file_store_usage(&total, &used);
    lv_label_set_text_fmt(_storage, "%d fotos, %d sange, %u MB fri", LV_MAX(photos, 0), LV_MAX(music, 0),
                          (unsigned)((total - used) / (1024 * 1024)));
}

void Sync::updateUi(void)
{
    ble_sync_state_t state;
    std::string payload;
    {
        std::lock_guard<std::mutex> lock(status.mutex);
        if (!status.dirty) {
            return;
        }
        status.dirty = false;
        state = status.state;
        payload = status.qr_payload;
    }

    lv_label_set_text(_status, state_text(state));

    const bool pairing = (state == BLE_SYNC_STATE_PAIRING) && !payload.empty();
    if (pairing) {
        lv_qrcode_update(_qr, payload.c_str(), payload.size());
        lv_label_set_text(_pop, pop_from_payload(payload).c_str());
        lv_obj_remove_flag(_qr, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(_pop, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_add_flag(_qr, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(_pop, LV_OBJ_FLAG_HIDDEN);
    }
    // The storage line and the reset button share the space below the status with the QR code
    if (pairing) {
        lv_obj_add_flag(_storage, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(_reset_button, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_remove_flag(_storage, LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(_reset_button, LV_OBJ_FLAG_HIDDEN);
    }
}

void Sync::onTimer(lv_timer_t *timer)
{
    Sync *app = static_cast<Sync *>(lv_timer_get_user_data(timer));
    if (app->_status == nullptr) {
        return;
    }
    if (++app->_ticks % BLE_TICK_EVERY == 0) {
        ble_sync_tick();
    }
    app->updateUi();

    // Upload progress replaces the status text while a file comes in
    uint32_t received = 0, size = 0;
    if (file_store_upload_progress(&received, &size) && (size > 0)) {
        lv_label_set_text_fmt(app->_status, "Modtager fil... %u%%", (unsigned)((uint64_t)received * 100 / size));
        app->_uploading = true;
    } else if (app->_uploading) {
        app->_uploading = false;
        app->updateStorageInfo();
        std::lock_guard<std::mutex> lock(status.mutex);
        status.dirty = true;    // Back to the connection status text
    }
}

void Sync::onResetPairing(lv_event_t *e)
{
    ble_sync_reset_pairing();
}

ESP_UTILS_REGISTER_PLUGIN_WITH_CONSTRUCTOR(systems::base::App, Sync, APP_NAME, []()
{
    return std::shared_ptr<Sync>(Sync::requestInstance(), [](Sync * p) {});
})

} // namespace esp_brookesia::apps
