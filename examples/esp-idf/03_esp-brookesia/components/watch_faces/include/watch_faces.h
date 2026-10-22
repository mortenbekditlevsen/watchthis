#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Customizable watch faces, implemented in Embedded Swift (format: docs/watch-face-format.md). The builtin faces
 * plus the ones uploaded from the phone (file_store kinds FILE_STORE_FACE / FILE_STORE_FACE_ASSET); the user swipes
 * left/right between them. Only the face on screen is built (LVGL objects, fonts, hand bitmaps). */

/* Once at boot, after file_store_mount(): installs the file_store hooks (face validation, change notices). */
void watch_faces_init(void);

/* Create the faces screen, load it and start updating; from the app's run(), with the LVGL lock held. */
void watch_faces_show(void);

/* Stop updating and free the faces; from the app's close(), with the LVGL lock held. The screen itself is deleted by
 * the app framework (it was created in run()), which frees what's on it. */
void watch_faces_hide(void);

/* Battery percentage for battery elements (-1 = unknown); polled about every 30 s while a face shows one. */
void watch_faces_set_battery_source(int (*percent)(void));

/* For ble_sync's face handlers (docs/watch-ble-protocol.md §12); from the BLE host task. */
int watch_faces_get_state(uint8_t *buf, size_t max);
uint8_t watch_faces_set_order(const uint8_t *payload, size_t len);
/* The wearer's birthday (month 1-12, day 1-31; 0/0 = none): a Danish flag on the faces that day. Returns a Result
 * status (0 = OK, 1 = failed, 2 = invalid). */
uint8_t watch_faces_set_birthday(uint8_t month, uint8_t day);
/* JSON array of the face features this firmware draws (for DEVICE_INFO) */
const char *watch_faces_features_json(void);

#ifdef __cplusplus
}
#endif
