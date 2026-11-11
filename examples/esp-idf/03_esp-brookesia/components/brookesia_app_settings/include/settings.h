/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* The settings saved by Indstillinger (NVS, namespace "settings"), applied at boot: call after nvs_flash_init() and
 * before the screen is turned on */
void settings_restore(void);

/* The night clock's brightness (1...100 %) */
int settings_night_brightness(void);

/* The night clock is switched on (Indstillinger, "Nattilstand") */
bool settings_night_clock_enabled(void);

/* What the "Prøv nattilstand" button does (the power manager shows the night clock for a while) */
void settings_set_try_night_handler(void (*try_night)(void));

#ifdef __cplusplus
}
#endif
