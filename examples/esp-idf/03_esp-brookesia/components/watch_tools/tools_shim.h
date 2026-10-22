// What Swift can't import from LVGL / ESP-IDF directly (macros, addresses of const globals, 64-bit atomics).
#pragma once

#include "lvgl.h"
#include "watch_fonts.h"

static inline int32_t wt_radius_circle(void) { return LV_RADIUS_CIRCLE; }
static inline int32_t wt_pct(int32_t v) { return LV_PCT(v); }

/* 20 and 28: Montserrat with ÆØÅæøå; 44: Montserrat; 66: the big condensed digits */
static inline const lv_font_t *wt_font(int size)
{
    switch (size) {
    case 28: return &watch_font_danish_28;
    case 44: return &lv_font_montserrat_44;
    case 66: return &watch_font_number_66;
    default: return &watch_font_danish_20;
    }
}

/* For a value read by the power task and written by the LVGL task (the storage is a Swift global) */
static inline int64_t wt_atomic_load64(int64_t *p) { return __atomic_load_n(p, __ATOMIC_SEQ_CST); }
static inline void wt_atomic_store64(int64_t *p, int64_t v) { __atomic_store_n(p, v, __ATOMIC_SEQ_CST); }
static inline int32_t wt_size_content(void) { return LV_SIZE_CONTENT; }
