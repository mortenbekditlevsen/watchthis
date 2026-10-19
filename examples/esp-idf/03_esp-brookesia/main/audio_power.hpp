/*
 * SPDX-License-Identifier: CC0-1.0
 */
#pragma once

/**
 * @brief Put the audio codec (ES8311) and the microphone ADC (ES7210) into their low-power state. They run from the
 *        main 3.3 V rail (DCDC1, shared with the ESP32), so they can't be switched off at the PMU. Uses the suspend
 *        sequences of esp_codec_dev's drivers; whatever plays audio later re-initializes them through esp_codec_dev.
 */
void audio_power_down(void);
