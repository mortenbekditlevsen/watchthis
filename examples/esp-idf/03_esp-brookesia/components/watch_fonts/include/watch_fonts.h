/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include "lvgl.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Montserrat 20/28 with the Danish letters (ÆØÅæøå), which LVGL's built-in Montserrat lacks: fonts with only those
 * glyphs that fall back to lv_font_montserrat_20/28 for everything else. */
LV_FONT_DECLARE(watch_font_danish_20);
LV_FONT_DECLARE(watch_font_danish_28);
/* 66 px condensed light oblique, ASCII (0x20-0x7F and °); the big digital clock font */
LV_FONT_DECLARE(watch_font_number_66);

#ifdef __cplusplus
}
#endif
