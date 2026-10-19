# BSP: Waveshare ESP32-C6-Touch-AMOLED-2.06

[![Component Registry](https://components.espressif.com/components/waveshare/esp32_c6_touch_amoled_2_06/badge.svg)](https://components.espressif.com/components/waveshare/esp32_c6_touch_amoled_2_06)

The ESP32-C6-Touch-AMOLED-2.06 is a 2.06-inch 410×502 capacitive touch development board designed by waveshare electronics.

|                            HW version                            | BSP Version |
|:----------------------------------------------------------------:| :---------: |
| [V1.0](http://www.waveshare.com/wiki/ESP32-C6-Touch-AMOLED-2.06) |      ^1     |
## Local changes (this project)

Copied from the managed component `waveshare/esp32_c6_touch_amoled_2_06` 2.0.0, which this local component
overrides (same name). Added for the watch's sleep mode:

- `bsp_display_sleep(bool)`: AMOLED controller DISPOFF+SLPIN / SLPOUT+DISPON.
- `bsp_touch_sleep(bool)`: touch controller hibernate (power mode register 0xA5 = 0x03) / wake via reset pulse.
