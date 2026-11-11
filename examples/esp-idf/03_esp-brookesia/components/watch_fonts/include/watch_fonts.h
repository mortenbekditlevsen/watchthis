/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include "lvgl.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Montserrat 8...44 with the Danish letters (ÆØÅæøå), which LVGL's built-in Montserrat lacks: fonts with only those
 * glyphs that fall back to lv_font_montserrat_N for everything else (generated with lv_font_conv; see their headers) */
LV_FONT_DECLARE(watch_font_danish_8);
LV_FONT_DECLARE(watch_font_danish_10);
LV_FONT_DECLARE(watch_font_danish_12);
LV_FONT_DECLARE(watch_font_danish_14);
LV_FONT_DECLARE(watch_font_danish_16);
LV_FONT_DECLARE(watch_font_danish_18);
LV_FONT_DECLARE(watch_font_danish_20);
LV_FONT_DECLARE(watch_font_danish_22);
LV_FONT_DECLARE(watch_font_danish_24);
LV_FONT_DECLARE(watch_font_danish_26);
LV_FONT_DECLARE(watch_font_danish_28);
LV_FONT_DECLARE(watch_font_danish_30);
LV_FONT_DECLARE(watch_font_danish_32);
LV_FONT_DECLARE(watch_font_danish_34);
LV_FONT_DECLARE(watch_font_danish_36);
LV_FONT_DECLARE(watch_font_danish_38);
LV_FONT_DECLARE(watch_font_danish_40);
LV_FONT_DECLARE(watch_font_danish_42);
LV_FONT_DECLARE(watch_font_danish_44);
/* 66 px condensed light oblique, ASCII (0x20-0x7F and °); the big digital clock font */
LV_FONT_DECLARE(watch_font_number_66);

#ifdef __cplusplus
}
#endif
