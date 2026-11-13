/*
 * SPDX-FileCopyrightText: 2024-2025 Espressif Systems (Shanghai) CO LTD
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include "systems/base/esp_brookesia_base_context.hpp"
#include "systems/phone/assets/esp_brookesia_phone_assets.h"
#include "../shell_fonts.hpp"

namespace esp_brookesia::systems::phone {

constexpr uint32_t STYLESHEET_410_502_DARK_CORE_DISPLAY_BG_COLOR = 0x1A1A1A;

constexpr base::Display::Data STYLESHEET_410_502_DARK_CORE_DISPLAY_DATA = {
    .background = {
        .color = gui::StyleColor::COLOR(STYLESHEET_410_502_DARK_CORE_DISPLAY_BG_COLOR),
        .wallpaper_image_resource = NULL,
    },
    .text = {
        .default_fonts_num = 21,
        .default_fonts = {
            gui::StyleFont::CUSTOM_SIZE(8, &shell_font_8),
            gui::StyleFont::CUSTOM_SIZE(10, &shell_font_10),
            gui::StyleFont::CUSTOM_SIZE(12, &shell_font_12),
            gui::StyleFont::CUSTOM_SIZE(14, &shell_font_14),
            gui::StyleFont::CUSTOM_SIZE(16, &shell_font_16),
            gui::StyleFont::CUSTOM_SIZE(18, &shell_font_18),
            gui::StyleFont::CUSTOM_SIZE(20, &shell_font_20),
            gui::StyleFont::CUSTOM_SIZE(22, &shell_font_22),
            gui::StyleFont::CUSTOM_SIZE(24, &shell_font_24),
            gui::StyleFont::CUSTOM_SIZE(26, &shell_font_26),
            gui::StyleFont::CUSTOM_SIZE(28, &shell_font_28),
            gui::StyleFont::CUSTOM_SIZE(30, &shell_font_30),
            gui::StyleFont::CUSTOM_SIZE(32, &shell_font_32),
            gui::StyleFont::CUSTOM_SIZE(34, &shell_font_34),
            gui::StyleFont::CUSTOM_SIZE(36, &shell_font_36),
            gui::StyleFont::CUSTOM_SIZE(38, &shell_font_38),
            gui::StyleFont::CUSTOM_SIZE(40, &shell_font_40),
            gui::StyleFont::CUSTOM_SIZE(42, &shell_font_42),
            gui::StyleFont::CUSTOM_SIZE(44, &shell_font_44),
            gui::StyleFont::CUSTOM_SIZE(46, &shell_font_46),
            gui::StyleFont::CUSTOM_SIZE(48, &shell_font_48),
        },
    },
    .container = {
        .styles = {
            { .outline_width = 1, .outline_color = gui::StyleColor::COLOR(0xeb3b5a), },
            { .outline_width = 2, .outline_color = gui::StyleColor::COLOR(0xfa8231), },
            { .outline_width = 1, .outline_color = gui::StyleColor::COLOR(0xf7b731), },
            { .outline_width = 2, .outline_color = gui::StyleColor::COLOR(0x20bf6b), },
            { .outline_width = 1, .outline_color = gui::StyleColor::COLOR(0x0fb9b1), },
            { .outline_width = 2, .outline_color = gui::StyleColor::COLOR(0x2d98da), },
        },
    },
};

constexpr base::Manager::Data STYLESHEET_410_502_DARK_CORE_MANAGER_DATA = {
    // One app at a time: home pauses it (opening it again resumes it), opening another app closes it first. And no
    // snapshots (for the recents screen, which is off): with no PSRAM, several paused apps' memory and a ~400 KB
    // screen snapshot per pause led to out-of-memory crashes
    .app = {
        .max_running_num = 1,
    },
    .flags = {
        .enable_app_save_snapshot = 0,
    },
};

constexpr const char *STYLESHEET_410_502_DARK_CORE_INFO_DATA_NAME = "Default Dark";

constexpr base::Context::Data STYLESHEET_410_502_DARK_CORE_DATA = {
    .name = STYLESHEET_410_502_DARK_CORE_INFO_DATA_NAME,
    .screen_size = gui::StyleSize::RECT(410, 502),
    .display = STYLESHEET_410_502_DARK_CORE_DISPLAY_DATA,
    .manager = STYLESHEET_410_502_DARK_CORE_MANAGER_DATA,
};

} // namespace esp_brookesia::systems::phone
