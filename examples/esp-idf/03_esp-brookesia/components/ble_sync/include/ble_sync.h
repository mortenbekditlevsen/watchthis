/*
 * SPDX-License-Identifier: CC0-1.0
 */
#ifndef __BLE_SYNC_H__
#define __BLE_SYNC_H__

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* BLE link to the paired phone (time sync, later file upload), implemented in Embedded Swift on NimBLE. Pairing
 * is app-level (QR code with a proof-of-possession code; see docs/watch-ble-protocol.md); all commands after
 * pairing are AES-GCM encrypted. BLE only runs between ble_sync_start() and ble_sync_stop(), which frees its
 * memory again. Plain C so Swift's ClangImporter can parse it. */

typedef enum {
    BLE_SYNC_STATE_OFF = 0,
    BLE_SYNC_STATE_STARTING,        /* Waiting for the BLE host to come up */
    BLE_SYNC_STATE_ADVERTISING,     /* Paired: waiting for the phone to connect */
    BLE_SYNC_STATE_PAIRING,         /* Pairing window open: show the QR code */
    BLE_SYNC_STATE_CONNECTED,       /* A phone is connected, not (yet) authenticated */
    BLE_SYNC_STATE_SESSION,         /* The paired phone is connected and authenticated */
    BLE_SYNC_STATE_ERROR,
} ble_sync_state_t;

/* Called on every state change, from the BLE host task or the caller of ble_sync_*(): must not block or take the
 * LVGL lock (copy and return). `qr_payload` is the QR code text while PAIRING, otherwise NULL; it is only valid
 * during the call. */
typedef void (*ble_sync_status_cb_t)(ble_sync_state_t state, const char *qr_payload);

/* Handles a SetTime command (UTC seconds; POSIX TZ string, may be empty = unchanged), from the BLE host task. */
typedef bool (*ble_sync_set_time_cb_t)(int64_t utc, const char *tz);

/* Install the SetTime handler (once, at boot). */
void ble_sync_set_time_handler(ble_sync_set_time_cb_t cb);

/* Handles a SetName command (the watch's name, UTF-8, 1..32 bytes; NUL-terminated), from the BLE host task. Returns
 * false if the name isn't acceptable. */
typedef bool (*ble_sync_set_name_cb_t)(const char *name);

/* Install the SetName handler (once, at boot). */
void ble_sync_set_name_handler(ble_sync_set_name_cb_t cb);

/* Returns the watch's name for a GetName command (from the BLE host task; NUL-terminated UTF-8). */
typedef const char *(*ble_sync_get_name_cb_t)(void);

/* Install the GetName handler (once, at boot). */
void ble_sync_get_name_handler(ble_sync_get_name_cb_t cb);

/* Start BLE: init NimBLE, register the GATT service and advertise; opens a pairing window if no phone is paired
 * yet. Returns false if BLE couldn't be started (e.g. out of memory). */
bool ble_sync_start(ble_sync_status_cb_t status_cb);

/* Disconnect, stop advertising and shut NimBLE down completely (frees its memory). Blocks until done. */
void ble_sync_stop(void);

bool ble_sync_is_active(void);

/* Forget the paired phone and open a fresh pairing window (new QR code). Only while active. */
void ble_sync_reset_pairing(void);

/* Call about once a second while active: expires a stale pairing window. */
void ble_sync_tick(void);

#ifdef __cplusplus
}
#endif

#endif
