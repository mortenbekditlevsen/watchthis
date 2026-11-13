/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include "lvgl.h"

/* The shell's font (Maison Neue, brookesia_core) has ASCII only. These are copies of it in RAM (its descriptors are
 * const) that fall back to Montserrat with the Danish letters (components/watch_fonts) for anything else, so names
 * like "Bøger" show. The stylesheet (dark/core_data.hpp) uses them; shell_fonts_init() fills them in, before the
 * shell starts. */
#define SHELL_FONT_SIZES(X) X(8) X(10) X(12) X(14) X(16) X(18) X(20) X(22) X(24) X(26) X(28) X(30) X(32) X(34) \
    X(36) X(38) X(40) X(42) X(44) X(46) X(48)

#define SHELL_FONT_DECLARE(size) extern lv_font_t shell_font_##size;
SHELL_FONT_SIZES(SHELL_FONT_DECLARE)

void shell_fonts_init(void);
