/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include "systems/phone/esp_brookesia_phone_app.hpp"

namespace esp_brookesia::apps {

/* The "Stopur" app: a shell around the Swift UI in components/watch_tools */
class Stopwatch: public systems::phone::App {
public:
    static Stopwatch *requestInstance();

    ~Stopwatch();

protected:
    Stopwatch();

    bool run(void) override;
    bool back(void) override;
    bool close(void) override;

private:
    static Stopwatch *_instance;
};

} // namespace esp_brookesia::apps
