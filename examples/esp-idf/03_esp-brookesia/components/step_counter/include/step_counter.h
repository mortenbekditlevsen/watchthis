/*
 * SPDX-License-Identifier: CC0-1.0
 */
#ifndef __STEP_COUNTER_H__
#define __STEP_COUNTER_H__

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Daily step count from the QMI8658 IMU's accelerometer: it buffers ~4 s of samples in its FIFO, which is drained
 * and run through a step detector about once a second (by an own task while awake, by step_counter_poll() from the
 * power manager between light sleeps). Keeps a per-day total across reboots and PMU power-offs (steps while powered
 * off aren't counted) in NVS, and rolls over to "yesterday" at local midnight. Thread-safe. */

/* Start the accelerometer and the polling task, and load the saved day. Needs NVS. */
bool step_counter_init(void);

/* Steps today / yesterday (local time; needs a valid clock, else everything counts as "today"). */
uint32_t step_counter_today(void);
uint32_t step_counter_yesterday(void);

/* Persist the current state (call e.g. hourly and before powering off). Cheap to call more often: only writes when
 * something changed. */
void step_counter_save(void);

/* Drain the FIFO if the last drain was ~1 s ago (cheap otherwise): call between light sleeps. */
void step_counter_poll(void);

/* Calibration aid: log the acceleration magnitudes of the next ~2 s of drains. */
void step_counter_trace(void);

#ifdef __cplusplus
}
#endif

#endif
