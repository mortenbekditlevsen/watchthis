/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include "systems/phone/esp_brookesia_phone_app.hpp"

namespace esp_brookesia::apps {

/* The "Julekalender" app (an advent calendar): a shell around the Swift app in components/watch_faces */
class Advent: public systems::phone::App {
public:
    static Advent *requestInstance();

    ~Advent();

protected:
    Advent();

    bool run(void) override;
    bool back(void) override;
    bool close(void) override;

private:
    static Advent *_instance;
};

} // namespace esp_brookesia::apps
