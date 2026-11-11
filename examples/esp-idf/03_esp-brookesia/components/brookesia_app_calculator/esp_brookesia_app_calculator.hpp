/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include "systems/phone/esp_brookesia_phone_app.hpp"

namespace esp_brookesia::apps {

/* The "Lommeregner" app (a calculator): a shell around the Swift calculator in components/watch_faces */
class Calculator: public systems::phone::App {
public:
    static Calculator *requestInstance();

    ~Calculator();

protected:
    Calculator();

    bool run(void) override;
    bool back(void) override;
    bool close(void) override;

private:
    static Calculator *_instance;
};

} // namespace esp_brookesia::apps
