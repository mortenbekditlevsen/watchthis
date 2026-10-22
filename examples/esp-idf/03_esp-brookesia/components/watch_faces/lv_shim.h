// What Swift can't import from LVGL directly (function-like macros, `const` globals it can't take the address of),
// as static inline functions. Only for components/watch_faces' Swift code.
#pragma once

#include "lvgl.h"
#include "watch_fonts.h"

static inline int32_t wf_pct(int32_t v) { return LV_PCT(v); }
static inline int32_t wf_size_content(void) { return LV_SIZE_CONTENT; }
static inline int32_t wf_radius_circle(void) { return LV_RADIUS_CIRCLE; }

static inline const lv_font_t *wf_builtin_font(int size)
{
    switch (size) {
    case 8: return &lv_font_montserrat_8;
    case 10: return &lv_font_montserrat_10;
    case 12: return &lv_font_montserrat_12;
    case 14: return &lv_font_montserrat_14;
    case 16: return &lv_font_montserrat_16;
    case 18: return &lv_font_montserrat_18;
    case 22: return &lv_font_montserrat_22;
    case 24: return &lv_font_montserrat_24;
    case 26: return &lv_font_montserrat_26;
    case 30: return &lv_font_montserrat_30;
    case 32: return &lv_font_montserrat_32;
    case 34: return &lv_font_montserrat_34;
    case 36: return &lv_font_montserrat_36;
    case 38: return &lv_font_montserrat_38;
    case 40: return &lv_font_montserrat_40;
    case 42: return &lv_font_montserrat_42;
    case 44: return &lv_font_montserrat_44;
    case 66: return &watch_font_number_66;
    // 20 and 28 with the Danish letters (ÆØÅæøå), falling back to Montserrat for the rest
    case 28: return &watch_font_danish_28;
    default: return &watch_font_danish_20;
    }
}

// lv_image_dsc_t's header is a bitfield struct; filling it here keeps Swift away from the bit layout
static inline void wf_image_dsc_init(lv_image_dsc_t *dsc, lv_color_format_t cf, uint32_t w, uint32_t h,
                                     uint32_t stride, const void *data, uint32_t data_size)
{
    lv_memzero(dsc, sizeof(*dsc));
    dsc->header.magic = LV_IMAGE_HEADER_MAGIC;
    dsc->header.cf = cf;
    dsc->header.w = w;
    dsc->header.h = h;
    dsc->header.stride = stride;
    dsc->data = (const uint8_t *)data;
    dsc->data_size = data_size;
}

static inline lv_point_precise_t wf_point(int32_t x, int32_t y)
{
    lv_point_precise_t p = {x, y};
    return p;
}

// Shared state between the LVGL task and the image worker task
static inline int32_t wf_atomic_load(volatile int32_t *p) { return __atomic_load_n(p, __ATOMIC_SEQ_CST); }
static inline void wf_atomic_store(volatile int32_t *p, int32_t v) { __atomic_store_n(p, v, __ATOMIC_SEQ_CST); }

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static inline bool wf_task_create(void (*fn)(void *), const char *name, uint32_t stack, UBaseType_t priority)
{
    return xTaskCreate(fn, name, stack, NULL, priority, NULL) == pdPASS;
}

// lv_draw_triangle_dsc_t's points are a C array (a tuple in Swift)
static inline void wf_draw_triangle(lv_layer_t *layer, int32_t x1, int32_t y1, int32_t x2, int32_t y2, int32_t x3,
                                    int32_t y3, lv_color_t color, lv_opa_t opa)
{
    lv_draw_triangle_dsc_t dsc;
    lv_draw_triangle_dsc_init(&dsc);
    dsc.p[0].x = x1; dsc.p[0].y = y1;
    dsc.p[1].x = x2; dsc.p[1].y = y2;
    dsc.p[2].x = x3; dsc.p[2].y = y3;
    dsc.color = color;
    dsc.opa = opa;
    lv_draw_triangle(layer, &dsc);
}

// For StoreImageDecoder.swift: LVGL's decoder descriptor fields are private, headers are bitfields
#include "src/draw/lv_image_decoder_private.h"
static inline int32_t wf_coord_min(void) { return LV_COORD_MIN; }
static inline void wf_image_header_set(lv_image_header_t *header, uint32_t w, uint32_t h)
{
    header->cf = LV_COLOR_FORMAT_RGB565;
    header->w = w;
    header->h = h;
    header->stride = w * 2;
}
static inline void wf_draw_buf_set_height(lv_draw_buf_t *buf, uint32_t h) { buf->header.h = h; }

// Diagnostics: the pixels LVGL is about to redraw (the display's invalid areas, joined ones skipped)
#include "src/display/lv_display_private.h"
static inline uint32_t wf_display_invalid_areas(lv_display_t *disp) { return disp->inv_p; }
static inline uint32_t wf_display_invalid_pixels(lv_display_t *disp)
{
    uint32_t px = 0;
    for (uint32_t i = 0; i < disp->inv_p; i++) {
        if (!disp->inv_area_joined[i]) {
            px += lv_area_get_size(&disp->inv_areas[i]);
        }
    }
    return px;
}

#include <fcntl.h>
// open() is variadic (Swift can't call it)
static inline int wf_open_read(const char *path) { return open(path, O_RDONLY); }
