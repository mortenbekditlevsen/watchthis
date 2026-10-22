#pragma once
#include "esp_lcd_touch.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief BSP touch configuration structure
 *
 */
typedef struct {
    void *dummy;    /*!< Prepared for future use. */
} bsp_touch_config_t;

/**
 * @brief Create new touchscreen
 *
 * If you want to free resources allocated by this function, you can use esp_lcd_touch API, ie.:
 *
 * \code{.c}
 * esp_lcd_touch_del(tp);
 * \endcode
 *
 * @param[in]  config    touch configuration
 * @param[out] ret_touch esp_lcd_touch touchscreen handle
 * @return
 *      - ESP_OK         On success
 *      - Else           esp_lcd_touch failure
 */
esp_err_t bsp_touch_new(const bsp_touch_config_t *config, esp_lcd_touch_handle_t *ret_touch);

/**
 * @brief Put the touch controller into hibernate (lowest power, no touch detection), or wake it with a reset pulse
 *        (~200 ms). [Local addition to Waveshare's BSP, see README.md]
 */
esp_err_t bsp_touch_sleep(bool sleep);

/**
 * @brief Whether a finger is on the screen (reads the touch controller; it must not be hibernating)
 */
bool bsp_touch_is_pressed(void);

/**
 * @brief Give the touch INT pin's interrupt back to the touch driver (falling edge, its handler), after it was
 *        used for something else
 */
void bsp_touch_restore_int(void);

#ifdef __cplusplus
}
#endif