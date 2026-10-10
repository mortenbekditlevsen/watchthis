#ifndef __PARTICLE_H__
#define __PARTICLE_H__

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Plain-data particle record shared between the C/LVGL rendering side
 * (brookesia_app_particles) and the Swift simulation side
 * (ParticleEffects.swift, via BridgingHeader.h). Deliberately has no LVGL
 * types in it -- only C's fixed-width integers cross the Swift <-> C
 * boundary, so Swift never needs to see (and Embedded Swift's ClangImporter
 * never needs to parse) any of LVGL's headers. */
typedef struct {
    int32_t sx, sy;   // screen-space position, tile-relative pixels
    int32_t size;     // on-screen size in px
    uint16_t hue;     // 0-359; C turns this into an lv_color_t right before drawing
    uint8_t sat;      // 0-100 HSV saturation
    uint8_t opa;      // 0-255 opacity
} particle_t;

/* The largest effect (Spirograph) uses 160 particles. */
#define PARTICLE_MAX_COUNT 160

/* Implemented in Swift (see ParticleEffects.swift). Called once per tick by
 * the renderer's particle timer: fills particles[0 ..< *out_count]
 * (out_count clamped to `capacity`) for whichever effect is currently
 * selected on the Swift side -- C has no idea which effect that is, or how
 * many exist. `reset` is true on the first tick after the renderer starts,
 * so the effect can (re)initialize its state. */
void particle_effect_tick(
    particle_t *particles,
    int32_t capacity,
    int32_t *out_count,
    int32_t tile_w,
    int32_t tile_h,
    bool reset
);

#ifdef __cplusplus
}
#endif

#endif
