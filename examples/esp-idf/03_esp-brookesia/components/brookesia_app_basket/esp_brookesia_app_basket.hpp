/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include "systems/phone/esp_brookesia_phone_app.hpp"

namespace esp_brookesia::apps {

/* The "Basket" app (a swipe basketball game): a shell around the Swift game in components/watch_faces */
class Basket: public systems::phone::App {
public:
    static Basket *requestInstance();

    ~Basket();

protected:
    Basket();

    bool run(void) override;
    bool back(void) override;
    bool close(void) override;

private:
    static Basket *_instance;
};

} // namespace esp_brookesia::apps
