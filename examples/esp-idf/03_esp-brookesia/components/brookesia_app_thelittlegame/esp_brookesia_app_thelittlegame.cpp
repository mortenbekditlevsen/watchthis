/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include "driver/gpio.h"
#include "esp_timer.h"
#include "lvgl.h"
#include "esp_brookesia.hpp"
#ifdef ESP_UTILS_LOG_TAG
#   undef ESP_UTILS_LOG_TAG
#endif
#define ESP_UTILS_LOG_TAG "BS:LittleGame"
#include "esp_lib_utils.h"
#include "esp_brookesia_app_thelittlegame.hpp"

#define APP_NAME "Det lille spil"

// Same frame period as the LED-matrix build's run loop
constexpr uint32_t GAME_TICK_MS = 30;
constexpr gpio_num_t BOOT_BUTTON_GPIO = GPIO_NUM_9;     // Active low

constexpr int32_t PIXEL_GAP = 2;
constexpr int32_t PIXEL_RADIUS = 6;
constexpr uint32_t PIXEL_BORDER_COLOR = 0x1A1A1A;       // Faint outline so unlit pixels still read as a matrix
constexpr int32_t SECTION_GAP = 24;
// Touch classification by distance between press and release: below TAP_MAX_MOVE is a tap ("fire"), above
// SWIPE_MIN_MOVE a swipe, anything in between is ignored. Done here instead of with LVGL's gesture detection, which
// misses slow swipes and then reports them as clicks.
constexpr int32_t TAP_MAX_MOVE = 15;
constexpr int32_t SWIPE_MIN_MOVE = 40;

using namespace esp_brookesia::systems;

LV_IMG_DECLARE(esp_brookesia_app_icon_launcher_thelittlegame_112_112);

namespace esp_brookesia::apps {

TheLittleGame *TheLittleGame::_instance = nullptr;

TheLittleGame *TheLittleGame::requestInstance()
{
    if (_instance == nullptr) {
        _instance = new TheLittleGame();
    }
    return _instance;
}

TheLittleGame::TheLittleGame():
    App(APP_NAME, &esp_brookesia_app_icon_launcher_thelittlegame_112_112, true, false, false)
{
}

TheLittleGame::~TheLittleGame()
{
}

bool TheLittleGame::run(void)
{
    ESP_UTILS_LOGD("Run");

    // Everything created here is recorded by the core and cleaned up when the app closes
    lv_obj_t *screen = lv_screen_active();
    lv_obj_set_style_bg_color(screen, lv_color_black(), 0);
    lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);
    lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_event_cb(screen, onScreenEvent, LV_EVENT_PRESSED, this);
    lv_obj_add_event_cb(screen, onScreenEvent, LV_EVENT_RELEASED, this);

    // Lay out: the pixel matrix, then a hint, vertically centered as one block
    lv_obj_update_layout(screen);
    const int32_t screen_w = lv_obj_get_width(screen);
    const int32_t screen_h = lv_obj_get_height(screen);
    const int32_t pitch = (screen_w - 2 * PIXEL_GAP) / LITTLEGAME_WIDTH;
    const int32_t pixel_size = pitch - PIXEL_GAP;
    const int32_t grid_w = LITTLEGAME_WIDTH * pitch - PIXEL_GAP;
    const int32_t grid_h = LITTLEGAME_HEIGHT * pitch - PIXEL_GAP;
    const int32_t hint_h = 20;
    const int32_t block_h = grid_h + SECTION_GAP + hint_h;
    const int32_t grid_x = (screen_w - grid_w) / 2;
    const int32_t grid_y = (screen_h - block_h) / 2;

    for (int row = 0; row < LITTLEGAME_HEIGHT; row++) {
        for (int x = 0; x < LITTLEGAME_WIDTH; x++) {
            lv_obj_t *pixel = lv_obj_create(screen);
            lv_obj_remove_style_all(pixel);
            lv_obj_remove_flag(pixel, LV_OBJ_FLAG_CLICKABLE);
            lv_obj_set_size(pixel, pixel_size, pixel_size);
            lv_obj_set_pos(pixel, grid_x + x * pitch, grid_y + row * pitch);
            lv_obj_set_style_radius(pixel, PIXEL_RADIUS, 0);
            lv_obj_set_style_bg_opa(pixel, LV_OPA_COVER, 0);
            lv_obj_set_style_bg_color(pixel, lv_color_black(), 0);
            lv_obj_set_style_border_width(pixel, 1, 0);
            lv_obj_set_style_border_color(pixel, lv_color_hex(PIXEL_BORDER_COLOR), 0);
            _pixels[row * LITTLEGAME_WIDTH + x] = pixel;
        }
    }

    lv_obj_t *hint = lv_label_create(screen);
    lv_label_set_text(hint, "Swipe: retning   Tryk: skyd   BOOT: skift spil");
    lv_obj_set_style_text_font(hint, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(hint, lv_color_hex(0x666666), 0);
    lv_obj_align(hint, LV_ALIGN_TOP_MID, 0, grid_y + grid_h + SECTION_GAP);

    // Force every pixel to be pushed on the first tick
    for (auto &c : _shown_rgb) {
        c = UINT32_MAX;
    }

    gpio_config_t boot_cfg = {};
    boot_cfg.pin_bit_mask = 1ULL << BOOT_BUTTON_GPIO;
    boot_cfg.mode = GPIO_MODE_INPUT;
    boot_cfg.pull_up_en = GPIO_PULLUP_ENABLE;
    ESP_UTILS_CHECK_ERROR_RETURN(gpio_config(&boot_cfg), false, "Configure BOOT button failed");
    _boot_level = gpio_get_level(BOOT_BUTTON_GPIO);

    _timer = lv_timer_create(onTick, GAME_TICK_MS, this);
    onTick(_timer);

    return true;
}

bool TheLittleGame::back(void)
{
    ESP_UTILS_LOGD("Back");

    ESP_UTILS_CHECK_FALSE_RETURN(notifyCoreClosed(), false, "Notify core closed failed");

    return true;
}

bool TheLittleGame::close(void)
{
    ESP_UTILS_LOGD("Close");

    // The core deletes the recorded timer and objects itself; the game's own state lives on in Swift
    _timer = nullptr;
    for (auto &p : _pixels) {
        p = nullptr;
    }

    return true;
}

bool TheLittleGame::pause(void)
{
    ESP_UTILS_LOGD("Pause");

    if (_timer != nullptr) {
        lv_timer_pause(_timer);
    }

    return true;
}

bool TheLittleGame::resume(void)
{
    ESP_UTILS_LOGD("Resume");

    if (_timer != nullptr) {
        lv_timer_resume(_timer);
    }

    return true;
}

void TheLittleGame::onTick(lv_timer_t *timer)
{
    TheLittleGame *app = static_cast<TheLittleGame *>(lv_timer_get_user_data(timer));
    if (app->_pixels[0] == nullptr) {
        return;
    }

    // BOOT button: act on the press (falling edge), like the physical game's buttons
    int boot_level = gpio_get_level(BOOT_BUTTON_GPIO);
    if (app->_boot_level == 1 && boot_level == 0) {
        thelittlegame_button(LITTLEGAME_BUTTON_SELECT);
    }
    app->_boot_level = boot_level;

    thelittlegame_tick(esp_timer_get_time() / 1e6, app->_rgb);

    for (int i = 0; i < PIXEL_COUNT; i++) {
        const uint8_t *c = &app->_rgb[i * 3];
        uint32_t rgb = (c[0] << 16) | (c[1] << 8) | c[2];
        if (rgb != app->_shown_rgb[i]) {
            lv_obj_set_style_bg_color(app->_pixels[i], lv_color_hex(rgb), 0);
            app->_shown_rgb[i] = rgb;
        }
    }
}

void TheLittleGame::onScreenEvent(lv_event_t *e)
{
    TheLittleGame *app = static_cast<TheLittleGame *>(lv_event_get_user_data(e));
    lv_indev_t *indev = lv_indev_active();
    if (indev == nullptr) {
        return;
    }

    lv_point_t point;
    lv_indev_get_point(indev, &point);

    if (lv_event_get_code(e) == LV_EVENT_PRESSED) {
        app->_press_point = point;
        return;
    }

    const int32_t dx = point.x - app->_press_point.x;
    const int32_t dy = point.y - app->_press_point.y;
    const int32_t move = LV_MAX(LV_ABS(dx), LV_ABS(dy));

    int32_t button;
    if (move < TAP_MAX_MOVE) {
        button = LITTLEGAME_BUTTON_FIRE;
    } else if (move < SWIPE_MIN_MOVE) {
        return;
    } else if (LV_ABS(dx) > LV_ABS(dy)) {
        button = (dx > 0) ? LITTLEGAME_BUTTON_RIGHT : LITTLEGAME_BUTTON_LEFT;
    } else {
        button = (dy > 0) ? LITTLEGAME_BUTTON_DOWN : LITTLEGAME_BUTTON_UP;
    }
    thelittlegame_button(button);
}

ESP_UTILS_REGISTER_PLUGIN_WITH_CONSTRUCTOR(systems::base::App, TheLittleGame, APP_NAME, []()
{
    return std::shared_ptr<TheLittleGame>(TheLittleGame::requestInstance(), [](TheLittleGame * p) {});
})

} // namespace esp_brookesia::apps
