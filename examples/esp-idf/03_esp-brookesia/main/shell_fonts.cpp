/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include <cstring>
#include "systems/phone/assets/esp_brookesia_phone_assets.h"
#include "watch_fonts.h"
#include "shell_fonts.hpp"

#define SHELL_FONT_DEFINE(size) lv_font_t shell_font_##size;
SHELL_FONT_SIZES(SHELL_FONT_DEFINE)

// The Danish fonts go up to 44 px: the two bigger sizes take that one's letters
static const lv_font_t *danish(int size)
{
    switch (size) {
#define DANISH_CASE(n) case n: return &watch_font_danish_##n;
        DANISH_CASE(8) DANISH_CASE(10) DANISH_CASE(12) DANISH_CASE(14) DANISH_CASE(16) DANISH_CASE(18)
        DANISH_CASE(20) DANISH_CASE(22) DANISH_CASE(24) DANISH_CASE(26) DANISH_CASE(28) DANISH_CASE(30)
        DANISH_CASE(32) DANISH_CASE(34) DANISH_CASE(36) DANISH_CASE(38) DANISH_CASE(40) DANISH_CASE(42)
#undef DANISH_CASE
    default: return &watch_font_danish_44;
    }
}

void shell_fonts_init(void)
{
#define SHELL_FONT_COPY(size)                                                                       \
    memcpy(&shell_font_##size, &esp_brookesia_font_maison_neue_book_##size, sizeof(lv_font_t));    \
    shell_font_##size.fallback = danish(size);
    SHELL_FONT_SIZES(SHELL_FONT_COPY)
#undef SHELL_FONT_COPY
}
