/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

/* Bluetooth sync without the Synk app while charging (ble_sync_set_background): the UI decides (cheap, from an LVGL
 * timer), a low-priority task starts/stops BLE, which takes a while and mustn't freeze the screen. */

/* Start the task (once, at boot). */
void ble_background_start(void);

/* Whether background BLE is wanted now; applied by the task within ~0.2 s. Any task. */
void ble_background_want(bool want);
