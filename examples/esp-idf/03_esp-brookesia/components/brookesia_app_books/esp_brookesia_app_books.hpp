/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include "systems/phone/esp_brookesia_phone_app.hpp"

namespace esp_brookesia::apps {

/* The "Bøger" app (books from the phone): a shell around the Swift reader in components/watch_faces */
class Books: public systems::phone::App {
public:
    static Books *requestInstance();

    ~Books();

protected:
    Books();

    bool run(void) override;
    bool back(void) override;
    bool close(void) override;

private:
    static Books *_instance;
};

} // namespace esp_brookesia::apps
