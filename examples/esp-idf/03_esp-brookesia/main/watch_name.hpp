/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include <cstddef>
#include "lvgl.h"

/* The watch's name, shown as the home screen title. Kept in NVS; the paired phone can change it (Synk, SetName). */

constexpr size_t WATCH_NAME_MAX_LEN = 32;   // Bytes of UTF-8

/* Load the name from NVS. On the first boot (nothing stored yet) `initial_name` is stored and used from then on. */
void watch_name_init(const char *initial_name);

/* The current name (valid until the next watch_name_set()). */
const char *watch_name_get(void);

/* Show the name in this label, also after later changes. Call with the LVGL lock held. */
void watch_name_attach_label(lv_obj_t *label);

/* Validate (1..WATCH_NAME_MAX_LEN bytes, no control characters), store and show a new name. From any task except
 * the LVGL task (takes the LVGL lock). */
bool watch_name_set(const char *name);
