/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/* The settings saved by Indstillinger (NVS, namespace "settings"), applied at boot: call after nvs_flash_init() and
 * before the screen is turned on */
void settings_restore(void);

#ifdef __cplusplus
}
#endif
