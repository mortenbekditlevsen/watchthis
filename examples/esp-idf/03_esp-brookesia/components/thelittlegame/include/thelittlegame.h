#ifndef __THELITTLEGAME_H__
#define __THELITTLEGAME_H__

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* The game's LED matrix */
#define LITTLEGAME_WIDTH  10
#define LITTLEGAME_HEIGHT 6

#define LITTLEGAME_BUTTON_UP     0
#define LITTLEGAME_BUTTON_DOWN   1
#define LITTLEGAME_BUTTON_LEFT   2
#define LITTLEGAME_BUTTON_RIGHT  3
#define LITTLEGAME_BUTTON_SELECT 4
#define LITTLEGAME_BUTTON_FIRE   5

/* Implemented in Swift (WatchBridge.swift). Renders one frame at `time` (seconds, monotonic) into
 * rgb[LITTLEGAME_WIDTH * LITTLEGAME_HEIGHT * 3] (row-major, top row first, 0-255 per channel). The physical
 * game's red/blue indicator LEDs (Screen.red/.blue) aren't shown on the watch. */
void thelittlegame_tick(double time, uint8_t *rgb);

/* Implemented in Swift. One of the LITTLEGAME_BUTTON_* values. */
void thelittlegame_button(int32_t button);

#ifdef __cplusplus
}
#endif

#endif
