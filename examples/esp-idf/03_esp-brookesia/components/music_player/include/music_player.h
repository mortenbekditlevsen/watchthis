/*
 * SPDX-License-Identifier: CC0-1.0
 */
#ifndef __MUSIC_PLAYER_H__
#define __MUSIC_PLAYER_H__

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* MP3 playback of the music in the file store (uploaded via Synk), on the speaker (ES8311 + amplifier). Runs in the
 * background, independent of any app: it has its own control task, and the decoder (~45 KB RAM) only exists while a
 * track is playing or paused. Tracks play in order (sorted by id) and playback stops after the last one; paused
 * playback stops by itself after a while. All functions are non-blocking and thread-safe. */

typedef enum {
    MUSIC_PLAYER_STOPPED = 0,
    MUSIC_PLAYER_PLAYING,
    MUSIC_PLAYER_PAUSED,
} music_player_state_t;

typedef struct {
    music_player_state_t state;
    int index;              /* Current track (also after stopping: where play continues), -1 = none */
    int count;              /* Tracks in the list */
    char title[64];         /* Current track's display name (or its id) */
    uint32_t elapsed_s;     /* Played time of the current track */
    int volume;             /* 0..100 */
} music_player_status_t;

/* Start the control task and load the volume. Call once at boot (cheap: no audio hardware is touched yet). */
bool music_player_init(void);

/* Re-read the track list from the file store (e.g. when the app opens; uploads may have changed it). */
void music_player_refresh(void);

/* Display name of track `index` of the current list (its id if it has none). */
bool music_player_track_title(int index, char *buf, size_t len);

void music_player_play(int index);
void music_player_toggle(void);     /* Pause/resume; starts the current track when stopped */
void music_player_next(void);
void music_player_prev(void);       /* Restarts the track if more than 3 s were played, else the previous one */
void music_player_stop(void);

/* Stop and wait until the decoder's memory is freed (up to `timeout_ms`): for code that needs that RAM itself, like
 * BLE. Must not be called from the music player's own callbacks. Returns false on timeout. */
bool music_player_stop_and_wait(uint32_t timeout_ms);

void music_player_set_volume(int volume);

void music_player_get_status(music_player_status_t *status);

/* True while audio is playing: the watch mustn't enter light sleep then (it would stop the sound). */
bool music_player_is_playing(void);

/* Timer alarm: beeps on the speaker until music_player_alarm_stop() or for at most a minute; stops the music first.
 * While it sounds the watch mustn't enter light sleep either. */
void music_player_alarm_start(void);
void music_player_alarm_stop(void);
bool music_player_alarm_active(void);

/* True while playing or paused (the audio hardware is in use). */
bool music_player_is_active(void);

#ifdef __cplusplus
}
#endif

#endif
