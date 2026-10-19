/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include "lvgl.h"

/**
 * @brief LVGL image decoder for the photos: baseline JPEG files (e.g. in the file store), drawn strip by strip.
 *
 * LVGL renders the screen in strips (the display buffer height), and its built-in TJPGD decoder decodes the whole
 * JPEG from the top for every strip. This decoder instead keeps one TJPGD session (and the open file) across strips
 * and draws: it only decodes as far as the requested strip, keeps the last decoded MCU row (full image width) in a
 * small RGB565 buffer, and only restarts from the top when an earlier part of the image is needed. A full redraw is
 * one decode pass.
 */
void cats_jpeg_decoder_init(void);

/**
 * @brief Point `dsc` at the JPEG file `path` for lv_image_set_src(). The path is copied into one of two internal
 *        slots used alternately, so the previously shown source stays valid while LVGL switches.
 */
void cats_jpeg_decoder_make_src(lv_image_dsc_t *dsc, const char *path);

/**
 * @brief Close the file and free the session's buffers (~18 KB). The decoder stays registered and reallocates on
 *        demand.
 */
void cats_jpeg_decoder_release(void);
