/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include <cstring>
#include <ctime>
#include <mutex>
#include "bsp/esp-bsp.h"
#include "esp_attr.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs.h"
#include "step_counter.h"

static const char *TAG = "Steps";

// QMI8658A. Its hardware pedometer never counts on this board (the "step detected" flag doesn't fire either), so the
// accelerometer fills the IMU's FIFO and steps are detected here, from the FIFO, about once a second (also between
// light sleeps: the power manager calls step_counter_poll())
static constexpr uint8_t QMI8658_ADDR = 0x6B;
static constexpr uint8_t REG_WHOAMI = 0x00;
static constexpr uint8_t WHOAMI_VALUE = 0x05;
static constexpr uint8_t REG_CTRL1 = 0x02;
static constexpr uint8_t REG_CTRL2 = 0x03;      // Accel range (bits 6:4) + ODR (bits 3:0)
static constexpr uint8_t REG_CTRL7 = 0x08;      // Bit 0: accel enable
static constexpr uint8_t REG_CTRL8 = 0x09;      // Bit 7: CTRL9 handshake via STATUSINT.7
static constexpr uint8_t REG_CTRL9 = 0x0A;
static constexpr uint8_t REG_FIFO_WTM_TH = 0x13;
static constexpr uint8_t REG_FIFO_CTRL = 0x14;  // Bits 1:0 mode, bits 3:2 size
static constexpr uint8_t REG_FIFO_SMPL_CNT = 0x15;  // Followed by FIFO_STATUS (0x16)
static constexpr uint8_t REG_FIFO_DATA = 0x17;
static constexpr uint8_t REG_STATUS_INT = 0x2D;
static constexpr uint8_t REG_RST_RESULT = 0x4D;
static constexpr uint8_t RST_RESULT_DONE = 0x80;
static constexpr uint8_t REG_RESET = 0x60;
static constexpr uint8_t CMD_ACK = 0x00;
static constexpr uint8_t CMD_RST_FIFO = 0x04;
static constexpr uint8_t CMD_REQ_FIFO = 0x05;
static constexpr uint8_t CTRL2_ACCEL_4G_31HZ = (1 << 4) | 8;
static constexpr int ACCEL_LSB_PER_G = 8192;
static constexpr uint8_t FIFO_CTRL_STREAM_128 = (3 << 2) | 2;
static constexpr size_t FIFO_SAMPLE_BYTES = 6;  // Accelerometer only
static constexpr size_t FIFO_MAX_BYTES = 128 * FIFO_SAMPLE_BYTES;
static constexpr size_t FIFO_READ_CHUNK = 20 * FIFO_SAMPLE_BYTES;
static constexpr int I2C_TIMEOUT_MS = 100;

static constexpr int64_t POLL_INTERVAL_US = 900 * 1000;    // The FIFO holds ~4 s
static constexpr uint32_t TASK_PERIOD_MS = 1000;

// Step detector, at 31.25 Hz on the acceleration magnitude (mg): a step is a peak of the smoothed magnitude above
// its running mean, after it dipped below the mean again, at least MIN_GAP after the previous one. A walk only counts
// once ENTRY_STEPS steps came in a row (none more than MAX_GAP apart): screens out arm movements and bumps
static constexpr int PEAK_MG = 100;
static constexpr int REARM_MG = 0;
static constexpr int MIN_GAP_SAMPLES = 8;       // 0.26 s
static constexpr int MAX_GAP_SAMPLES = 62;      // 2 s
static constexpr int ENTRY_STEPS = 6;

static constexpr const char *NVS_NAMESPACE = "steps";

static i2c_master_dev_handle_t imu = nullptr;
static std::mutex lock;
static bool ready = false;
static int64_t last_poll_us = 0;
static int64_t trace_until_us = 0;

// today = offset + detected. The offset absorbs what makes the detector's count differ from today's total: steps
// from before a power-off and the count at midnight. Plain struct (no initializers): a constructor would overwrite
// the RTC copy at boot
struct State {
    int32_t offset;
    uint32_t today_saved;       // Today's total at the last save (restored after a power-off)
    uint32_t yesterday;
    int32_t date;               // YYYYMMDD of "today", 0 = unknown clock
};
static State saved;             // What NVS holds, to skip redundant writes

// Kept in RTC memory: survives software resets and crashes (not power loss), so the steps since the last NVS save
// aren't lost then
static constexpr uint32_t RTC_MAGIC = 0x57E95C01;
static RTC_NOINIT_ATTR uint32_t rtc_magic;
static RTC_NOINIT_ATTR State state;
static RTC_NOINIT_ATTR uint32_t detected;

struct Detector {
    int window[4] = {};
    int window_pos = 0;
    int32_t mean = -1;          // Running mean of the smoothed magnitude, x16; -1 = not started
    bool armed = false;
    int since_step = MAX_GAP_SAMPLES + 1;
    int pending = 0;            // Steps of a walk that hasn't reached ENTRY_STEPS yet
    bool walking = false;
};
static Detector detector;

static bool reg_write(uint8_t reg, uint8_t value)
{
    uint8_t buf[2] = {reg, value};
    return i2c_master_transmit(imu, buf, sizeof(buf), I2C_TIMEOUT_MS) == ESP_OK;
}

static bool reg_read(uint8_t reg, uint8_t *data, size_t len)
{
    return i2c_master_transmit_receive(imu, &reg, 1, data, len, I2C_TIMEOUT_MS) == ESP_OK;
}

static bool ctrl9_command(uint8_t cmd)
{
    if (!reg_write(REG_CTRL9, cmd)) {
        return false;
    }
    for (int i = 0; i < 100; i++) {     // Wait for "command done" (STATUSINT.7)
        uint8_t status = 0;
        if (reg_read(REG_STATUS_INT, &status, 1) && (status & 0x80)) {
            reg_write(REG_CTRL9, CMD_ACK);
            for (int j = 0; j < 100; j++) {
                if (reg_read(REG_STATUS_INT, &status, 1) && !(status & 0x80)) {
                    return true;
                }
                vTaskDelay(pdMS_TO_TICKS(1));
            }
            return false;
        }
        vTaskDelay(pdMS_TO_TICKS(1));
    }
    ESP_LOGE(TAG, "CTRL9 command 0x%02x timed out", cmd);
    return false;
}

// Reset, accelerometer only (31.25 Hz, +-4 g) streaming into the 128-sample FIFO
static bool start_imu(void)
{
    reg_write(REG_RESET, 0xB0);
    uint8_t rst = 0;
    for (int i = 0; (i < 50) && (rst != RST_RESULT_DONE); i++) {
        vTaskDelay(pdMS_TO_TICKS(10));
        reg_read(REG_RST_RESULT, &rst, 1);
    }
    uint8_t id = 0;
    if (!reg_read(REG_WHOAMI, &id, 1) || (id != WHOAMI_VALUE)) {
        ESP_LOGE(TAG, "QMI8658 not found (id 0x%02x)", id);
        return false;
    }
    uint8_t ctrl1 = 0;
    reg_read(REG_CTRL1, &ctrl1, 1);
    reg_write(REG_CTRL1, ctrl1 | 0x40); // Address auto-increment, little-endian
    reg_write(REG_CTRL8, 0x80);         // CTRL9 handshake via STATUSINT.7, no motion engines
    reg_write(REG_CTRL7, 0x00);
    reg_write(REG_CTRL2, CTRL2_ACCEL_4G_31HZ);
    if (!ctrl9_command(CMD_RST_FIFO)) {
        return false;
    }
    reg_write(REG_FIFO_CTRL, FIFO_CTRL_STREAM_128);
    reg_write(REG_FIFO_WTM_TH, 64);
    return reg_write(REG_CTRL7, 0x01);  // Accelerometer on
}

static uint32_t isqrt(uint32_t v)
{
    uint32_t r = 0;
    for (uint32_t bit = 1u << 30; bit != 0; bit >>= 2) {
        if (v >= r + bit) {
            v -= r + bit;
            r = (r >> 1) + bit;
        } else {
            r >>= 1;
        }
    }
    return r;
}

static void detect_step_locked(int magnitude_mg)
{
    Detector &d = detector;
    d.window[d.window_pos] = magnitude_mg;
    d.window_pos = (d.window_pos + 1) % 4;
    const int smooth = (d.window[0] + d.window[1] + d.window[2] + d.window[3]) / 4;
    if (d.mean < 0) {
        d.mean = smooth * 16;
    }
    d.mean += smooth - d.mean / 16;     // ~0.5 s time constant
    const int above = smooth - d.mean / 16;

    if (d.since_step <= MAX_GAP_SAMPLES) {
        d.since_step++;
    } else if (d.pending || d.walking) {
        d.pending = 0;                  // The walk (or the attempt to start one) ended
        d.walking = false;
    }
    if (above < REARM_MG) {
        d.armed = true;
    }
    if (d.armed && (above > PEAK_MG) && (d.since_step >= MIN_GAP_SAMPLES)) {
        d.armed = false;
        d.since_step = 0;
        if (d.walking) {
            detected++;
        } else if (++d.pending >= ENTRY_STEPS) {
            detected += d.pending;
            d.pending = 0;
            d.walking = true;
        }
    }
}

// Empties the FIFO into the detector
static void drain_fifo_locked(bool trace)
{
    uint8_t cnt[2] = {};
    if (!reg_read(REG_FIFO_SMPL_CNT, cnt, sizeof(cnt))) {
        return;
    }
    if (!(cnt[1] & 0x10)) {
        return;                         // FIFO_STATUS.4: not empty
    }
    if (cnt[1] & 0x20) {
        ESP_LOGW(TAG, "FIFO overflow");
    }
    size_t bytes = 2 * (((cnt[1] & 0x03) << 8) | cnt[0]);
    bytes = (bytes > FIFO_MAX_BYTES) ? FIFO_MAX_BYTES : bytes - bytes % FIFO_SAMPLE_BYTES;
    if ((bytes == 0) || !ctrl9_command(CMD_REQ_FIFO)) {
        return;
    }

    char line[200];
    int line_len = 0;
    uint8_t buf[FIFO_READ_CHUNK];
    for (size_t pos = 0; pos < bytes; pos += sizeof(buf)) {
        const size_t len = (bytes - pos < sizeof(buf)) ? bytes - pos : sizeof(buf);
        if (!reg_read(REG_FIFO_DATA, buf, len)) {
            break;
        }
        for (size_t i = 0; i < len; i += FIFO_SAMPLE_BYTES) {
            const int32_t ax = (int16_t)(buf[i] | (buf[i + 1] << 8));
            const int32_t ay = (int16_t)(buf[i + 2] | (buf[i + 3] << 8));
            const int32_t az = (int16_t)(buf[i + 4] | (buf[i + 5] << 8));
            // Scale to mg first: the squared raw values could overflow 32 bits
            const int32_t mx = ax * 1000 / ACCEL_LSB_PER_G, my = ay * 1000 / ACCEL_LSB_PER_G,
                          mz = az * 1000 / ACCEL_LSB_PER_G;
            const int magnitude = (int)isqrt((uint32_t)(mx * mx + my * my + mz * mz));
            detect_step_locked(magnitude);
            if (trace) {
                line_len += snprintf(line + line_len, sizeof(line) - line_len, " %d", magnitude);
                if (line_len > (int)sizeof(line) - 12) {
                    ESP_LOGI(TAG, "trc%s", line);
                    line_len = 0;
                }
            }
        }
    }
    reg_write(REG_FIFO_CTRL, FIFO_CTRL_STREAM_128);     // Leave FIFO read mode
    if (trace) {
        if (line_len > 0) {
            ESP_LOGI(TAG, "trc%s", line);
        }
        ESP_LOGI(TAG, "trc end: detected %u, pending %d, walking %d", (unsigned)detected, detector.pending,
                 detector.walking);
    }
}

static int32_t today_date(void)
{
    time_t now = time(nullptr);
    struct tm t;
    localtime_r(&now, &t);
    if (t.tm_year + 1900 < 2024) {
        return 0;       // Clock not set yet
    }
    return (t.tm_year + 1900) * 10000 + (t.tm_mon + 1) * 100 + t.tm_mday;
}

static int32_t day_before(int32_t date)
{
    struct tm t = {};
    t.tm_year = date / 10000 - 1900;
    t.tm_mon = (date / 100) % 100 - 1;
    t.tm_mday = date % 100 - 1;
    t.tm_hour = 12;
    mktime(&t);         // Normalizes day 0 to the previous month's last day
    return (t.tm_year + 1900) * 10000 + (t.tm_mon + 1) * 100 + t.tm_mday;
}

static uint32_t total_locked(void)
{
    const int64_t total = (int64_t)state.offset + detected;
    return (total > 0) ? (uint32_t)total : 0;
}

// Midnight rollover (also after being asleep or off across midnight)
static void check_day_locked(void)
{
    const int32_t date = today_date();
    if ((date == 0) || (date == state.date)) {
        return;
    }
    if (state.date != 0) {
        state.yesterday = (day_before(date) == state.date) ? total_locked() : 0;
    }
    state.date = date;
    state.offset = -(int32_t)detected;  // Today starts at 0
    state.today_saved = 0;
}

static void poll_locked(bool force)
{
    const int64_t now = esp_timer_get_time();
    if (!ready || (!force && (now - last_poll_us < POLL_INTERVAL_US))) {
        return;
    }
    last_poll_us = now;
    drain_fifo_locked(now < trace_until_us);
    check_day_locked();
}

static void step_task(void *arg)
{
    while (true) {
        step_counter_poll();
        vTaskDelay(pdMS_TO_TICKS(TASK_PERIOD_MS));
    }
}

bool step_counter_init(void)
{
    std::lock_guard<std::mutex> guard(lock);

    i2c_master_bus_handle_t bus = bsp_i2c_get_handle();
    if (bus == nullptr) {
        return false;
    }
    i2c_device_config_t dev_cfg = {};
    dev_cfg.dev_addr_length = I2C_ADDR_BIT_LEN_7;
    dev_cfg.device_address = QMI8658_ADDR;
    dev_cfg.scl_speed_hz = 400000;
    if (i2c_master_bus_add_device(bus, &dev_cfg, &imu) != ESP_OK) {
        return false;
    }

    nvs_handle_t nvs;
    State nvs_state = {};
    if (nvs_open(NVS_NAMESPACE, NVS_READONLY, &nvs) == ESP_OK) {
        size_t len = sizeof(nvs_state);
        if ((nvs_get_blob(nvs, "state", &nvs_state, &len) != ESP_OK) || (len != sizeof(nvs_state))) {
            nvs_state = {};
        }
        nvs_close(nvs);
    }
    saved = nvs_state;
    if (rtc_magic != RTC_MAGIC) {
        // Power-on: the RTC copy is gone, continue from the last save
        state = nvs_state;
        detected = 0;
        state.offset = state.today_saved;
        rtc_magic = RTC_MAGIC;
    }

    if (!start_imu()) {
        return false;
    }
    check_day_locked();
    ready = true;
    last_poll_us = esp_timer_get_time();
    ESP_LOGI(TAG, "Today %u steps, yesterday %u", (unsigned)total_locked(), (unsigned)state.yesterday);

    xTaskCreate(step_task, "steps", 3 * 1024, nullptr, 2, nullptr);
    return true;
}

void step_counter_poll(void)
{
    std::lock_guard<std::mutex> guard(lock);
    poll_locked(false);
}

uint32_t step_counter_today(void)
{
    std::lock_guard<std::mutex> guard(lock);
    check_day_locked();
    return total_locked();
}

uint32_t step_counter_yesterday(void)
{
    std::lock_guard<std::mutex> guard(lock);
    check_day_locked();
    return state.yesterday;
}

void step_counter_save(void)
{
    std::lock_guard<std::mutex> guard(lock);
    if (!ready) {
        return;
    }
    poll_locked(true);
    state.today_saved = total_locked();
    if (memcmp(&state, &saved, sizeof(state)) == 0) {
        return;
    }
    nvs_handle_t nvs;
    if (nvs_open(NVS_NAMESPACE, NVS_READWRITE, &nvs) == ESP_OK) {
        nvs_set_blob(nvs, "state", &state, sizeof(state));
        nvs_commit(nvs);
        nvs_close(nvs);
        saved = state;
    }
}

void step_counter_trace(void)
{
    std::lock_guard<std::mutex> guard(lock);
    trace_until_us = esp_timer_get_time() + 2 * 1000 * 1000;
}
