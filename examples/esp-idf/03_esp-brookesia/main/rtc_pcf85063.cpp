/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include "bsp/esp-bsp.h"
#include "esp_log.h"
#include "rtc_pcf85063.hpp"

static const char *TAG = "RTC";

static constexpr uint8_t PCF85063_ADDR = 0x51;
static constexpr uint8_t PCF85063_REG_SECONDS = 0x04;   // Seconds, minutes, hours, days, weekdays, months, years
static constexpr uint8_t PCF85063_SECONDS_OS = 0x80;    // Oscillator stopped: time is not reliable
static constexpr int I2C_TIMEOUT_MS = 100;

static i2c_master_dev_handle_t rtc_dev = nullptr;

static uint8_t bcd2dec(uint8_t v)
{
    return (v >> 4) * 10 + (v & 0x0F);
}

static uint8_t dec2bcd(int v)
{
    return ((v / 10) << 4) | (v % 10);
}

// Days since 1970-01-01 for a proleptic Gregorian date (UTC, so mktime() and the TZ setting don't apply)
static time_t days_from_civil(int y, int m, int d)
{
    y -= m <= 2;
    const int era = y / 400;
    const int yoe = y - era * 400;
    const int doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    const int doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return static_cast<time_t>(era) * 146097 + doe - 719468;
}

static bool rtc_get_dev(void)
{
    if (rtc_dev != nullptr) {
        return true;
    }

    i2c_master_bus_handle_t bus = bsp_i2c_get_handle();
    if (bus == nullptr) {
        ESP_LOGE(TAG, "I2C bus not available");
        return false;
    }

    i2c_device_config_t dev_cfg = {};
    dev_cfg.dev_addr_length = I2C_ADDR_BIT_LEN_7;
    dev_cfg.device_address = PCF85063_ADDR;
    dev_cfg.scl_speed_hz = 400000;
    esp_err_t ret = i2c_master_bus_add_device(bus, &dev_cfg, &rtc_dev);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Add I2C device failed: %s", esp_err_to_name(ret));
        rtc_dev = nullptr;
        return false;
    }

    return true;
}

bool rtc_pcf85063_read(time_t *utc)
{
    if (!rtc_get_dev()) {
        return false;
    }

    uint8_t reg = PCF85063_REG_SECONDS;
    uint8_t buf[7];
    esp_err_t ret = i2c_master_transmit_receive(rtc_dev, &reg, 1, buf, sizeof(buf), I2C_TIMEOUT_MS);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Read failed: %s", esp_err_to_name(ret));
        return false;
    }
    if (buf[0] & PCF85063_SECONDS_OS) {
        ESP_LOGW(TAG, "Oscillator was stopped, time not valid");
        return false;
    }

    int sec = bcd2dec(buf[0] & 0x7F);
    int min = bcd2dec(buf[1] & 0x7F);
    int hour = bcd2dec(buf[2] & 0x3F);
    int day = bcd2dec(buf[3] & 0x3F);
    int month = bcd2dec(buf[5] & 0x1F);
    int year = 2000 + bcd2dec(buf[6]);
    *utc = days_from_civil(year, month, day) * 86400 + hour * 3600 + min * 60 + sec;

    return true;
}

bool rtc_pcf85063_write(time_t utc)
{
    if (!rtc_get_dev()) {
        return false;
    }

    struct tm t;
    gmtime_r(&utc, &t);

    uint8_t buf[8] = {
        PCF85063_REG_SECONDS,
        dec2bcd(t.tm_sec),  // Writing the seconds also clears the OS flag
        dec2bcd(t.tm_min),
        dec2bcd(t.tm_hour),
        dec2bcd(t.tm_mday),
        static_cast<uint8_t>(t.tm_wday),
        dec2bcd(t.tm_mon + 1),
        dec2bcd(t.tm_year % 100),
    };
    esp_err_t ret = i2c_master_transmit(rtc_dev, buf, sizeof(buf), I2C_TIMEOUT_MS);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Write failed: %s", esp_err_to_name(ret));
        return false;
    }

    return true;
}
