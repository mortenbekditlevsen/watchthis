/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include "systems/phone/esp_brookesia_phone_app.hpp"

namespace esp_brookesia::apps {

/* The "Tidstagning" app: a shell around the Swift UI in components/watch_tools */
class Timer: public systems::phone::App {
public:
    static Timer *requestInstance();

    ~Timer();

protected:
    Timer();

    bool run(void) override;
    bool back(void) override;
    bool close(void) override;

private:
    static Timer *_instance;
};

} // namespace esp_brookesia::apps
