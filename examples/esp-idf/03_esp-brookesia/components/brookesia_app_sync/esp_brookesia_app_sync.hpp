/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include "lvgl.h"
#include "systems/phone/esp_brookesia_phone_app.hpp"

namespace esp_brookesia::apps {

/**
 * @brief "Synk": runs BLE (components/ble_sync) while open, so the paired phone can set the time (and later upload
 *        files). Shows the pairing QR code when no phone is paired, the connection state otherwise, and lets the
 *        user forget the phone and pair a new one.
 */
class Sync: public systems::phone::App {
public:
    static Sync *requestInstance();

    ~Sync();

protected:
    Sync();

    bool run(void) override;
    bool back(void) override;
    bool close(void) override;
    bool pause(void) override;
    bool resume(void) override;

private:
    static void onTimer(lv_timer_t *timer);
    static void onResetPairing(lv_event_t *e);
    static void onConfirmReset(lv_event_t *e);
    static void onCancelReset(lv_event_t *e);

    void startBle(void);
    void stopBle(void);
    void updateUi(void);
    void updateStorageInfo(void);
    void showResetConfirmation(void);
    void closeResetConfirmation(void);

    static Sync *_instance;

    lv_obj_t *_status = nullptr;
    lv_obj_t *_qr = nullptr;
    lv_obj_t *_pop = nullptr;
    lv_obj_t *_storage = nullptr;
    lv_obj_t *_reset_button = nullptr;
    lv_obj_t *_confirm = nullptr;   // "Are you sure" over the whole screen, while shown
    uint32_t _ticks = 0;
    bool _uploading = false;
};

} // namespace esp_brookesia::apps
