/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include "systems/phone/esp_brookesia_phone_app.hpp"

namespace esp_brookesia::apps {

/* The "Weather" app: a shell around the Swift UI in components/watch_faces */
class Weather: public systems::phone::App {
public:
    static Weather *requestInstance();

    ~Weather();

protected:
    Weather();

    bool run(void) override;
    bool back(void) override;
    bool close(void) override;

private:
    static Weather *_instance;
};

} // namespace esp_brookesia::apps
