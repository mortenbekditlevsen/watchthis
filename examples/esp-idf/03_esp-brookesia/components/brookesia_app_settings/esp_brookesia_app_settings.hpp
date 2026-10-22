/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include "systems/phone/esp_brookesia_phone_app.hpp"

namespace esp_brookesia::apps {

/* "Indstillinger": the screen's brightness (saved, and restored at boot: settings_restore()) */
class Settings: public systems::phone::App {
public:
    static Settings *requestInstance();

    ~Settings();

protected:
    Settings();

    bool run(void) override;
    bool back(void) override;
    bool close(void) override;

private:
    static void onBrightnessChanged(lv_event_t *e);
    static void onBrightnessReleased(lv_event_t *e);

    static Settings *_instance;

    lv_obj_t *_value = nullptr;
};

} // namespace esp_brookesia::apps
