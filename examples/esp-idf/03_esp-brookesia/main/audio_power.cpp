/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include "bsp/esp-bsp.h"
#include "esp_log.h"
#include "audio_power.hpp"

static const char *TAG = "AudioPower";

static constexpr uint16_t ES8311_ADDR = 0x18;
static constexpr uint16_t ES7210_ADDR = 0x40;
static constexpr int I2C_TIMEOUT_MS = 100;

struct RegValue {
    uint8_t reg;
    uint8_t value;
};

// esp_codec_dev device/es8311/es8311.c: es8311_suspend()
static const RegValue ES8311_SUSPEND[] = {
    {0x32, 0x00}, {0x17, 0x00}, {0x0E, 0xFF}, {0x12, 0x02}, {0x14, 0x00}, {0x0D, 0xFA}, {0x15, 0x00},
    {0x02, 0x10}, {0x00, 0x00}, {0x00, 0x1F}, {0x01, 0x30}, {0x01, 0x00}, {0x45, 0x00}, {0x0D, 0xFC},
    {0x02, 0x00},
};

// esp_codec_dev device/es7210/es7210.c: es7210_stop()
static const RegValue ES7210_STOP[] = {
    {0x47, 0xFF}, {0x48, 0xFF}, {0x49, 0xFF}, {0x4A, 0xFF}, {0x4B, 0xFF}, {0x4C, 0xFF}, {0x40, 0xC0},
    {0x01, 0x7F}, {0x06, 0x07},
};

static bool write_sequence(uint16_t addr, const RegValue *seq, size_t count)
{
    i2c_master_bus_handle_t bus = bsp_i2c_get_handle();
    i2c_device_config_t cfg = {};
    cfg.dev_addr_length = I2C_ADDR_BIT_LEN_7;
    cfg.device_address = addr;
    cfg.scl_speed_hz = 100000;
    i2c_master_dev_handle_t dev = nullptr;
    if ((bus == nullptr) || (i2c_master_bus_add_device(bus, &cfg, &dev) != ESP_OK)) {
        return false;
    }
    bool ok = true;
    for (size_t i = 0; i < count; i++) {
        const uint8_t buf[2] = {seq[i].reg, seq[i].value};
        ok &= (i2c_master_transmit(dev, buf, sizeof(buf), I2C_TIMEOUT_MS) == ESP_OK);
    }
    i2c_master_bus_rm_device(dev);
    return ok;
}

void audio_power_down(void)
{
    const bool codec = write_sequence(ES8311_ADDR, ES8311_SUSPEND, sizeof(ES8311_SUSPEND) / sizeof(ES8311_SUSPEND[0]));
    const bool adc = write_sequence(ES7210_ADDR, ES7210_STOP, sizeof(ES7210_STOP) / sizeof(ES7210_STOP[0]));
    ESP_LOGI(TAG, "Audio chips powered down (codec %s, mic ADC %s)", codec ? "ok" : "failed", adc ? "ok" : "failed");
}
