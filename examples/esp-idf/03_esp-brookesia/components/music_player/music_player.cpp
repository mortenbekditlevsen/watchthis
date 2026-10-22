/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include <cmath>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <vector>
#include "audio_player.h"
#include "bsp/esp-bsp.h"
#include "esp_codec_dev.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "file_store.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "nvs.h"
#include "music_player.h"

static const char *TAG = "Music";

static constexpr int DEFAULT_VOLUME = 60;
static constexpr int64_t PAUSE_TIMEOUT_US = 10LL * 60 * 1000 * 1000;    // Paused this long: stop (frees the audio)
static constexpr int64_t PREV_RESTARTS_AFTER_US = 3 * 1000 * 1000;
static constexpr uint32_t TASK_STACK_SIZE = 4 * 1024;
static constexpr UBaseType_t TASK_PRIORITY = 4;
static constexpr UBaseType_t AUDIO_TASK_PRIORITY = 5;   // Above the UI, so drawing doesn't starve the audio
static constexpr const char *NVS_NAMESPACE = "music";

enum class Cmd : uint8_t { Play, Toggle, Next, Prev, Stop, TrackEnded, Volume, Tick, Alarm };

struct Message {
    Cmd cmd;
    int arg;
};

static QueueHandle_t queue = nullptr;
static std::mutex lock;                 // Guards everything below that the API reads

static std::vector<file_store_entry_t> tracks;
static music_player_state_t state = MUSIC_PLAYER_STOPPED;
static int current = -1;
static int volume = DEFAULT_VOLUME;
static int64_t play_started_us = 0;     // When the current track started, adjusted for pauses
static int64_t paused_at_us = 0;

// Audio hardware and decoder: only touched by the control task (and the audio task through the callbacks below)
static esp_codec_dev_handle_t speaker = nullptr;
static bool codec_open = false;
static bool player_created = false;
static volatile bool stop_requested = false;
static volatile int stream_channels = 1;
static volatile bool alarm_on = false;     // Set by the API; the control task beeps while it's true

// Alarm sound: bursts of four short beeps
static constexpr uint32_t ALARM_RATE = 16000;
static constexpr int ALARM_TONE_HZ = 2000;
static constexpr int ALARM_BEEP_MS = 90, ALARM_GAP_MS = 70, ALARM_BEEPS = 4, ALARM_PAUSE_MS = 600;
static constexpr int ALARM_MIN_VOLUME = 75;
static constexpr int64_t ALARM_MAX_US = 60LL * 1000 * 1000;

// ---- Audio callbacks (audio task) ----

static esp_err_t audio_mute(AUDIO_PLAYER_MUTE_SETTING setting)
{
    if (speaker != nullptr) {
        esp_codec_dev_set_out_mute(speaker, setting == AUDIO_PLAYER_MUTE);
    }
    return ESP_OK;
}

// The speaker is mono and the I2S bus is set up mono (it's shared with the microphone): the codec always runs one
// channel at the stream's sample rate, and stereo streams are mixed down in audio_write()
static esp_err_t audio_clock(uint32_t rate, uint32_t bits_cfg, i2s_slot_mode_t ch)
{
    stream_channels = (ch == I2S_SLOT_MODE_STEREO) ? 2 : 1;
    esp_codec_dev_sample_info_t fs = {};
    fs.bits_per_sample = 16;
    fs.channel = 1;
    fs.sample_rate = rate;
    if (codec_open) {
        esp_codec_dev_close(speaker);
        codec_open = false;
    }
    if (esp_codec_dev_open(speaker, &fs) != ESP_CODEC_DEV_OK) {
        ESP_LOGE(TAG, "Opening the codec at %u Hz failed", (unsigned)rate);
        return ESP_FAIL;
    }
    codec_open = true;
    int vol;
    {
        std::lock_guard<std::mutex> guard(lock);
        vol = volume;
    }
    esp_codec_dev_set_out_vol(speaker, vol);
    return ESP_OK;
}

static esp_err_t audio_write(void *buffer, size_t len, size_t *written, uint32_t timeout_ms)
{
    size_t out_len = len;
    if (stream_channels == 2) {
        int16_t *s = static_cast<int16_t *>(buffer);
        const size_t frames = len / 4;
        for (size_t i = 0; i < frames; i++) {
            s[i] = (int16_t)(((int32_t)s[2 * i] + s[2 * i + 1]) / 2);
        }
        out_len = frames * 2;
    }
    const bool ok = codec_open && (esp_codec_dev_write(speaker, buffer, (int)out_len) == ESP_CODEC_DEV_OK);
    *written = len;     // The player counts in input bytes
    return ok ? ESP_OK : ESP_FAIL;
}

static void audio_event(audio_player_cb_ctx_t *ctx)
{
    // Called on the audio task: only post, never call back into the player from here
    if ((ctx->audio_event == AUDIO_PLAYER_CALLBACK_EVENT_IDLE) && !stop_requested) {
        Message msg = {Cmd::TrackEnded, 0};
        xQueueSend(queue, &msg, 0);
    } else if (ctx->audio_event == AUDIO_PLAYER_CALLBACK_EVENT_UNKNOWN_FILE_TYPE) {
        ESP_LOGW(TAG, "Not a playable file");
        Message msg = {Cmd::TrackEnded, 0};
        xQueueSend(queue, &msg, 0);
    }
}

// ---- Control task ----

static void load_tracks_locked(void)
{
    const int count = file_store_list(FILE_STORE_MUSIC, nullptr, 0);
    tracks.assign((count > 0) ? count : 0, file_store_entry_t{});
    if (count > 0) {
        const int got = file_store_list(FILE_STORE_MUSIC, tracks.data(), count);
        tracks.resize((got < 0) ? 0 : ((got < count) ? got : count));
    }
    if (current >= (int)tracks.size()) {
        current = tracks.empty() ? -1 : 0;
    }
}

static bool ensure_player(void)
{
    if (speaker == nullptr) {
        speaker = bsp_audio_codec_speaker_init();
        if (speaker == nullptr) {
            ESP_LOGE(TAG, "Speaker not available");
            return false;
        }
    }
    if (!player_created) {
        audio_player_config_t config = {};
        config.mute_fn = audio_mute;
        config.clk_set_fn = audio_clock;
        config.write_fn = audio_write;
        config.priority = AUDIO_TASK_PRIORITY;
        config.coreID = 0;
        if (audio_player_new(config) != ESP_OK) {
            ESP_LOGE(TAG, "Not enough memory for the decoder (%u bytes free)",
                     (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL));
            return false;
        }
        audio_player_callback_register(audio_event, nullptr);
        player_created = true;
    }
    return true;
}

// Frees the decoder and puts the codec (and with it the amplifier) back to standby
static void release_player(void)
{
    if (player_created) {
        stop_requested = true;
        audio_player_stop();
        audio_player_delete();
        player_created = false;
    }
    if (codec_open) {
        esp_codec_dev_close(speaker);
        codec_open = false;
    }
}

static void set_state(music_player_state_t new_state)
{
    std::lock_guard<std::mutex> guard(lock);
    state = new_state;
}

static void start_track(int index)
{
    char path[FILE_STORE_PATH_MAX];
    {
        std::lock_guard<std::mutex> guard(lock);
        load_tracks_locked();
        if ((index < 0) || (index >= (int)tracks.size())) {
            state = MUSIC_PLAYER_STOPPED;
            return;
        }
        current = index;
        file_store_path(FILE_STORE_MUSIC, tracks[index].id, path, sizeof(path));
    }
    if (!ensure_player()) {
        set_state(MUSIC_PLAYER_STOPPED);
        return;
    }
    FILE *fp = fopen(path, "rb");
    if (fp == nullptr) {
        ESP_LOGE(TAG, "Can't open %s", path);
        set_state(MUSIC_PLAYER_STOPPED);
        return;
    }
    stop_requested = false;
    if (audio_player_play(fp) != ESP_OK) {      // The player closes the file
        fclose(fp);
        set_state(MUSIC_PLAYER_STOPPED);
        return;
    }
    std::lock_guard<std::mutex> guard(lock);
    state = MUSIC_PLAYER_PLAYING;
    play_started_us = esp_timer_get_time();
    ESP_LOGI(TAG, "Playing %d/%d: %s", index + 1, (int)tracks.size(), tracks[index].id);
}

static void stop(void)
{
    release_player();
    set_state(MUSIC_PLAYER_STOPPED);
}

// Writes the beep pattern until alarm_on is cleared (or a minute has passed). Blocks the control task meanwhile.
static void sound_alarm(void)
{
    stop();     // The music, if any: the alarm takes over the speaker
    if (speaker == nullptr) {
        speaker = bsp_audio_codec_speaker_init();
    }
    esp_codec_dev_sample_info_t fs = {};
    fs.sample_rate = ALARM_RATE;
    fs.channel = 1;
    fs.bits_per_sample = 16;
    if ((speaker == nullptr) || (esp_codec_dev_open(speaker, &fs) != ESP_CODEC_DEV_OK)) {
        ESP_LOGE(TAG, "Alarm: speaker not available");
        alarm_on = false;
        return;
    }
    int vol;
    {
        std::lock_guard<std::mutex> guard(lock);
        vol = (volume > ALARM_MIN_VOLUME) ? volume : ALARM_MIN_VOLUME;
    }
    esp_codec_dev_set_out_vol(speaker, vol);

    constexpr int CHUNK = ALARM_RATE / 100;     // 10 ms
    static int16_t samples[CHUNK];
    // One period of the tone (2 kHz at 16 kHz: 8 samples), so there's no sinf() per sample (no FPU on the C6)
    static_assert(ALARM_RATE % ALARM_TONE_HZ == 0, "the tone must be a whole number of samples per period");
    constexpr int PERIOD = ALARM_RATE / ALARM_TONE_HZ;
    float wave[PERIOD];
    for (int i = 0; i < PERIOD; i++) {
        wave[i] = sinf(2 * (float)M_PI * i / PERIOD);
    }
    constexpr int PERIOD_MS = ALARM_BEEPS * (ALARM_BEEP_MS + ALARM_GAP_MS) + ALARM_PAUSE_MS;
    const int64_t started = esp_timer_get_time();
    int64_t n = 0;  // Samples written
    while (alarm_on && (esp_timer_get_time() - started < ALARM_MAX_US)) {
        for (int i = 0; i < CHUNK; i++, n++) {
            const int ms = (int)((n * 1000 / ALARM_RATE) % PERIOD_MS);
            const int slot = ms / (ALARM_BEEP_MS + ALARM_GAP_MS);
            const int in_slot = ms % (ALARM_BEEP_MS + ALARM_GAP_MS);
            float amplitude = 0;
            if ((slot < ALARM_BEEPS) && (in_slot < ALARM_BEEP_MS)) {
                // 5 ms fade in and out, so the beeps don't click
                const float edge = fminf(in_slot, ALARM_BEEP_MS - in_slot) / 5.0f;
                amplitude = 12000 * fminf(1.0f, edge);
            }
            samples[i] = (int16_t)(amplitude * wave[n % PERIOD]);
        }
        if (esp_codec_dev_write(speaker, samples, sizeof(samples)) != ESP_CODEC_DEV_OK) {
            break;
        }
    }
    esp_codec_dev_close(speaker);
    alarm_on = false;
}

static void handle(const Message &msg)
{
    music_player_state_t st;
    int cur, count;
    {
        std::lock_guard<std::mutex> guard(lock);
        st = state;
        cur = current;
        count = (int)tracks.size();
    }

    switch (msg.cmd) {
    case Cmd::Play:
        start_track(msg.arg);
        break;
    case Cmd::Toggle:
        if (st == MUSIC_PLAYER_PLAYING) {
            audio_player_pause();
            std::lock_guard<std::mutex> guard(lock);
            state = MUSIC_PLAYER_PAUSED;
            paused_at_us = esp_timer_get_time();
        } else if (st == MUSIC_PLAYER_PAUSED) {
            audio_player_resume();
            std::lock_guard<std::mutex> guard(lock);
            state = MUSIC_PLAYER_PLAYING;
            play_started_us += esp_timer_get_time() - paused_at_us;
        } else {
            start_track((cur >= 0) ? cur : 0);
        }
        break;
    case Cmd::Next:
        if (cur + 1 < count) {
            start_track(cur + 1);
        }
        break;
    case Cmd::Prev: {
        int64_t played;
        {
            std::lock_guard<std::mutex> guard(lock);
            played = ((st == MUSIC_PLAYER_PAUSED) ? paused_at_us : esp_timer_get_time()) - play_started_us;
        }
        start_track(((played > PREV_RESTARTS_AFTER_US) || (cur <= 0)) ? cur : cur - 1);
        break;
    }
    case Cmd::Stop:
        stop();
        break;
    case Cmd::TrackEnded:
        if (st != MUSIC_PLAYER_PLAYING) {
            break;
        }
        if (cur + 1 < count) {
            start_track(cur + 1);
        } else {
            ESP_LOGI(TAG, "End of the list");
            stop();
            std::lock_guard<std::mutex> guard(lock);
            current = 0;
        }
        break;
    case Cmd::Volume:
        if (codec_open) {
            esp_codec_dev_set_out_vol(speaker, msg.arg);
        }
        break;
    case Cmd::Alarm:
        if (alarm_on) {
            sound_alarm();
        }
        break;
    case Cmd::Tick:
        if ((st == MUSIC_PLAYER_PAUSED) && (esp_timer_get_time() - paused_at_us > PAUSE_TIMEOUT_US)) {
            ESP_LOGI(TAG, "Paused too long, stopping");
            stop();
        }
        break;
    }
}

static void control_task(void *arg)
{
    Message msg;
    while (true) {
        if (xQueueReceive(queue, &msg, pdMS_TO_TICKS(10 * 1000)) != pdTRUE) {
            msg = {Cmd::Tick, 0};
        }
        handle(msg);
    }
}

static void post(Cmd cmd, int arg = 0)
{
    if (queue != nullptr) {
        Message msg = {cmd, arg};
        xQueueSend(queue, &msg, 0);
    }
}

// ---- API ----

bool music_player_init(void)
{
    if (queue != nullptr) {
        return true;
    }
    nvs_handle_t nvs;
    if (nvs_open(NVS_NAMESPACE, NVS_READONLY, &nvs) == ESP_OK) {
        int32_t v;
        if ((nvs_get_i32(nvs, "volume", &v) == ESP_OK) && (v >= 0) && (v <= 100)) {
            volume = v;
        }
        nvs_close(nvs);
    }
    queue = xQueueCreate(8, sizeof(Message));
    if ((queue == nullptr) ||
            (xTaskCreate(control_task, "music", TASK_STACK_SIZE, nullptr, TASK_PRIORITY, nullptr) != pdPASS)) {
        return false;
    }
    return true;
}

void music_player_refresh(void)
{
    std::lock_guard<std::mutex> guard(lock);
    load_tracks_locked();
    if ((current < 0) && !tracks.empty()) {
        current = 0;
    }
}

bool music_player_track_title(int index, char *buf, size_t len)
{
    std::lock_guard<std::mutex> guard(lock);
    if ((index < 0) || (index >= (int)tracks.size())) {
        return false;
    }
    const file_store_entry_t &t = tracks[index];
    strlcpy(buf, (t.name[0] != '\0') ? t.name : t.id, len);
    return true;
}

void music_player_play(int index)
{
    post(Cmd::Play, index);
}

void music_player_toggle(void)
{
    post(Cmd::Toggle);
}

void music_player_next(void)
{
    post(Cmd::Next);
}

void music_player_prev(void)
{
    post(Cmd::Prev);
}

void music_player_stop(void)
{
    post(Cmd::Stop);
}

bool music_player_stop_and_wait(uint32_t timeout_ms)
{
    if (!music_player_is_active()) {
        return true;
    }
    post(Cmd::Stop);
    // The state turns STOPPED only after the decoder is deleted and the codec closed (see stop())
    for (uint32_t waited = 0; music_player_is_active(); waited += 20) {
        if (waited >= timeout_ms) {
            return false;
        }
        vTaskDelay(pdMS_TO_TICKS(20));
    }
    return true;
}

void music_player_set_volume(int new_volume)
{
    new_volume = (new_volume < 0) ? 0 : ((new_volume > 100) ? 100 : new_volume);
    {
        std::lock_guard<std::mutex> guard(lock);
        if (new_volume == volume) {
            return;
        }
        volume = new_volume;
    }
    post(Cmd::Volume, new_volume);
    nvs_handle_t nvs;
    if (nvs_open(NVS_NAMESPACE, NVS_READWRITE, &nvs) == ESP_OK) {
        nvs_set_i32(nvs, "volume", new_volume);
        nvs_commit(nvs);
        nvs_close(nvs);
    }
}

void music_player_get_status(music_player_status_t *status)
{
    std::lock_guard<std::mutex> guard(lock);
    status->state = state;
    status->index = current;
    status->count = (int)tracks.size();
    status->volume = volume;
    status->title[0] = '\0';
    if ((current >= 0) && (current < (int)tracks.size())) {
        const file_store_entry_t &t = tracks[current];
        strlcpy(status->title, (t.name[0] != '\0') ? t.name : t.id, sizeof(status->title));
    }
    int64_t elapsed = 0;
    if (state == MUSIC_PLAYER_PLAYING) {
        elapsed = esp_timer_get_time() - play_started_us;
    } else if (state == MUSIC_PLAYER_PAUSED) {
        elapsed = paused_at_us - play_started_us;
    }
    status->elapsed_s = (uint32_t)(elapsed / 1000000);
}

void music_player_alarm_start(void)
{
    if (!alarm_on) {
        alarm_on = true;
        post(Cmd::Alarm);
    }
}

void music_player_alarm_stop(void)
{
    alarm_on = false;
}

bool music_player_alarm_active(void)
{
    return alarm_on;
}

bool music_player_is_playing(void)
{
    std::lock_guard<std::mutex> guard(lock);
    return state == MUSIC_PLAYER_PLAYING;
}

bool music_player_is_active(void)
{
    std::lock_guard<std::mutex> guard(lock);
    return state != MUSIC_PLAYER_STOPPED;
}
