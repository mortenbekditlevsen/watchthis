/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include "bsp/esp-bsp.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "pmu.hpp"

static const char *TAG = "PMU";

static constexpr uint8_t AXP2101_ADDR = 0x34;
static constexpr uint8_t AXP2101_REG_STATUS1 = 0x00;
static constexpr uint8_t AXP2101_STATUS1_VBUS_GOOD = 0x20;  // Bit 5
static constexpr uint8_t AXP2101_REG_STATUS2 = 0x01;
static constexpr uint8_t AXP2101_STATUS2_BATFET_OFF = 0x08; // Bit 3; must be clear for VBUS to be "in" (XPowersLib isVbusIn)
static constexpr uint8_t AXP2101_REG_COMMON_CONFIG = 0x10;     // Bit 0: power off
static constexpr uint8_t AXP2101_REG_GAUGE_CTRL = 0x18;        // Bit 3: fuel gauge enable
static constexpr uint8_t AXP2101_REG_PWROFF_EN = 0x22;         // Bit 1: long press powers off; bit 0: restart instead
static constexpr uint8_t AXP2101_REG_PKEY_TIMING = 0x27;       // Bits 3:2: off-press time (0 = 4 s)
static constexpr uint8_t AXP2101_REG_ADC_CTRL = 0x30;          // Bit 0: battery voltage measurement
static constexpr uint8_t AXP2101_REG_VBAT_H = 0x34;            // 13-bit battery voltage in mV (5 + 8 bits)
static constexpr uint8_t AXP2101_REG_BAT_PERCENT = 0xA4;
static constexpr uint8_t AXP2101_STATUS1_BAT_PRESENT = 0x08;   // Bit 3
static constexpr uint8_t AXP2101_REG_INTEN2 = 0x41;
static constexpr uint8_t AXP2101_REG_INTSTS2 = 0x49;    // Write 1 to clear
static constexpr uint8_t AXP2101_PKEY_SHORT = 0x08;     // Bit 3 in INTEN2/INTSTS2
static constexpr int I2C_TIMEOUT_MS = 100;

static i2c_master_dev_handle_t pmu_dev = nullptr;

static bool pmu_get_dev(void)
{
    if (pmu_dev != nullptr) {
        return true;
    }

    i2c_master_bus_handle_t bus = bsp_i2c_get_handle();
    if (bus == nullptr) {
        ESP_LOGE(TAG, "I2C bus not available");
        return false;
    }

    i2c_device_config_t dev_cfg = {};
    dev_cfg.dev_addr_length = I2C_ADDR_BIT_LEN_7;
    dev_cfg.device_address = AXP2101_ADDR;
    dev_cfg.scl_speed_hz = 400000;
    esp_err_t ret = i2c_master_bus_add_device(bus, &dev_cfg, &pmu_dev);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Add I2C device failed: %s", esp_err_to_name(ret));
        pmu_dev = nullptr;
        return false;
    }

    return true;
}

static bool pmu_read(uint8_t reg, uint8_t *value)
{
    return i2c_master_transmit_receive(pmu_dev, &reg, 1, value, 1, I2C_TIMEOUT_MS) == ESP_OK;
}

static bool pmu_write(uint8_t reg, uint8_t value)
{
    uint8_t buf[2] = {reg, value};
    return i2c_master_transmit(pmu_dev, buf, sizeof(buf), I2C_TIMEOUT_MS) == ESP_OK;
}

bool pmu_ensure_rails(void)
{
    if (!pmu_get_dev()) {
        return false;
    }
    // As found on a factory-fresh board: DCDC1..4 on; ALDO1..4, BLDO1..2, CPUSLDO, DLDO1 and DLDO2 on
    uint8_t dc = 0, ldo0 = 0, ldo1 = 0;
    pmu_read(0x80, &dc);
    pmu_read(0x90, &ldo0);
    pmu_read(0x91, &ldo1);
    if (((dc & 0x0F) != 0x0F) || (ldo0 != 0xFF) || !(ldo1 & 0x01)) {
        ESP_LOGW(TAG, "Rails were off (DC %02x, LDO %02x %02x), switching them back on", dc, ldo0, ldo1);
        pmu_write(0x80, dc | 0x0F);
        pmu_write(0x90, 0xFF);
        pmu_write(0x91, ldo1 | 0x01);
        vTaskDelay(pdMS_TO_TICKS(50));
    }
    return true;
}

// Charger: 300 mA constant current (~0.75C for the ~400 mAh cell; factory 200 mA) and charge termination at 50 mA
// (factory 125 mA, which stopped short of full). Kept below 1C: the battery temperature sensor isn't used on this
// board, so the charger can't back off when the cell gets warm
static constexpr uint8_t CHARGE_CURRENT_300MA = 9;      // 0x62 bits 4:0: 0..8 = n x 25 mA, 9..16 = 200 + (n - 8) x 100 mA
static constexpr uint8_t TERMINATION_50MA = 2;          // 0x63 bits 3:0, 25 mA steps (bit 4: termination enable)

static void configure_charger(void)
{
    uint8_t cc, term;
    if (pmu_read(0x62, &cc)) {
        pmu_write(0x62, (cc & ~0x1F) | CHARGE_CURRENT_300MA);
    }
    if (pmu_read(0x63, &term)) {
        pmu_write(0x63, (term & ~0x0F) | 0x10 | TERMINATION_50MA);
    }
}

// Charger settings as the PMU has them: precharge 0x61, constant current 0x62, termination 0x63, target voltage 0x64
static void log_charger_config(void)
{
    uint8_t pre, cc, term, cv;
    if (!pmu_read(0x61, &pre) || !pmu_read(0x62, &cc) || !pmu_read(0x63, &term) || !pmu_read(0x64, &cv)) {
        return;
    }
    const int cc_code = cc & 0x1F;
    const int cc_ma = (cc_code <= 8) ? cc_code * 25 : 200 + (cc_code - 8) * 100;
    static const char *const CV_NAMES[] = {"?", "4.0", "4.1", "4.2", "4.35", "4.4", "?", "?"};
    ESP_LOGI(TAG, "Charger: %d mA (0x62=0x%02x), precharge %d mA, termination %d mA%s, target %s V (0x64=0x%02x)",
             cc_ma, cc, (pre & 0x0F) * 25, (term & 0x0F) * 25, (term & 0x10) ? "" : " (off)", CV_NAMES[cv & 0x07], cv);
}

bool pmu_init(void)
{
    if (!pmu_get_dev()) {
        return false;
    }

    // The status bit only latches while its IRQ is enabled
    uint8_t inten2, gauge, adc, pwroff, timing;
    if (!pmu_read(AXP2101_REG_INTEN2, &inten2) || !pmu_write(AXP2101_REG_INTEN2, inten2 | AXP2101_PKEY_SHORT) ||
            !pmu_write(AXP2101_REG_INTSTS2, AXP2101_PKEY_SHORT)) {
        ESP_LOGE(TAG, "PMU access failed");
        return false;
    }
    // Battery: fuel gauge + voltage ADC
    if (pmu_read(AXP2101_REG_GAUGE_CTRL, &gauge)) {
        pmu_write(AXP2101_REG_GAUGE_CTRL, gauge | 0x08);
    }
    if (pmu_read(AXP2101_REG_ADC_CTRL, &adc)) {
        pmu_write(AXP2101_REG_ADC_CTRL, adc | 0x01);
    }
    // Holding the power key ~4 s switches the board off (not restart)
    if (pmu_read(AXP2101_REG_PWROFF_EN, &pwroff)) {
        pmu_write(AXP2101_REG_PWROFF_EN, (pwroff | 0x02) & ~0x01);
    }
    if (pmu_read(AXP2101_REG_PKEY_TIMING, &timing)) {
        pmu_write(AXP2101_REG_PKEY_TIMING, timing & ~0x0C);
    }

    configure_charger();
    log_charger_config();
    return true;
}

bool pmu_pkey_short_pressed(void)
{
    uint8_t status;
    if ((pmu_dev == nullptr) || !pmu_read(AXP2101_REG_INTSTS2, &status) || !(status & AXP2101_PKEY_SHORT)) {
        return false;
    }
    pmu_write(AXP2101_REG_INTSTS2, AXP2101_PKEY_SHORT);

    return true;
}

bool pmu_vbus_present(void)
{
    uint8_t status1, status2;
    if ((pmu_dev == nullptr) || !pmu_read(AXP2101_REG_STATUS1, &status1) || !pmu_read(AXP2101_REG_STATUS2, &status2)) {
        return false;
    }

    return (status1 & AXP2101_STATUS1_VBUS_GOOD) && !(status2 & AXP2101_STATUS2_BATFET_OFF);
}

bool pmu_battery(PmuBattery *battery)
{
    uint8_t status1, status2, vbat_h, vbat_l, percent;
    if ((pmu_dev == nullptr) || !pmu_read(AXP2101_REG_STATUS1, &status1) || !pmu_read(AXP2101_REG_STATUS2, &status2) ||
            !pmu_read(AXP2101_REG_VBAT_H, &vbat_h) || !pmu_read(AXP2101_REG_VBAT_H + 1, &vbat_l) ||
            !pmu_read(AXP2101_REG_BAT_PERCENT, &percent)) {
        return false;
    }
    battery->present = status1 & AXP2101_STATUS1_BAT_PRESENT;
    // Bits 6:5 = battery current direction (01 = charging); only trusted with USB power present, it can lag behind
    // an unplug
    const bool vbus = (status1 & AXP2101_STATUS1_VBUS_GOOD) && !(status2 & AXP2101_STATUS2_BATFET_OFF);
    battery->charging = vbus && ((status2 >> 5) == 0x01);
    battery->millivolts = ((vbat_h & 0x1F) << 8) | vbat_l;
    battery->percent = (battery->present && (percent <= 100)) ? percent : -1;

    return true;
}

void pmu_power_off(void)
{
    uint8_t config;
    ESP_LOGW(TAG, "Powering off");
    if ((pmu_dev != nullptr) && pmu_read(AXP2101_REG_COMMON_CONFIG, &config)) {
        pmu_write(AXP2101_REG_COMMON_CONFIG, config | 0x01);
    }
}
