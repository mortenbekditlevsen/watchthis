/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include "systems/phone/esp_brookesia_phone_app.hpp"

namespace esp_brookesia::apps {

/* The "Tegn" app (a small paint app): a shell around the Swift app in components/watch_faces */
class Paint: public systems::phone::App {
public:
    static Paint *requestInstance();

    ~Paint();

protected:
    Paint();

    bool run(void) override;
    bool back(void) override;
    bool close(void) override;

private:
    static Paint *_instance;
};

} // namespace esp_brookesia::apps
