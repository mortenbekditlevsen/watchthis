/*
 * SPDX-FileCopyrightText: 2024-2025 Espressif Systems (Shanghai) CO LTD
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include "systems/phone/widgets/app_launcher/esp_brookesia_app_launcher.hpp"

namespace esp_brookesia::systems::phone {

constexpr AppLauncherIcon::Data STYLESHEET_410_502_DARK_APP_LAUNCHER_ICON_DATA = {
    // Original icon/label sizes; cells are just tall enough for them (120 + 10 + label) so a 2x2 grid fits in the
    // launcher table below
    .main = {
        .size = gui::StyleSize::RECT(200, 155),
        .layout_row_pad = 10,
    },
    .image = {
        .default_size = gui::StyleSize::SQUARE(120),
        .press_size = gui::StyleSize::SQUARE(120),  // Same as default: no shrink while pressed (it showed during swipes)
    },
    .label = {
        .text_font = gui::StyleFont::SIZE(16),
        .text_color = gui::StyleColor::COLOR(0xFFFFFF),
    },
};

constexpr AppLauncherData STYLESHEET_410_502_DARK_APP_LAUNCHER_DATA = {
    // Placed by hand (enable_app_launcher_flex_size = 0 in stylesheet.hpp): below the 50 px status bar plus a 50 px
    // band for the home screen title (see main.cpp), down to the bottom of the screen
    .main = {
        .y_start = 100,
        .size = gui::StyleSize::RECT_PERCENT(100, 80),
    },
    .table = {
        .default_num = 3,
        .size = gui::StyleSize::RECT_PERCENT(100, 85),
    },
    .indicator = {
        .main_size = gui::StyleSize::RECT_W_PERCENT(100, 20),
        .main_layout_column_pad = 10,
        .main_layout_bottom_offset = 30,
        .spot_inactive_size = gui::StyleSize::SQUARE(12),
        .spot_active_size = gui::StyleSize::RECT(40, 12),
        .spot_inactive_background_color = gui::StyleColor::COLOR(0xC6C6C6),
        .spot_active_background_color = gui::StyleColor::COLOR(0xFFFFFF),
    },
    .icon = STYLESHEET_410_502_DARK_APP_LAUNCHER_ICON_DATA,
    .flags = {
        .enable_table_scroll_anim = 0,
    },
};

} // namespace esp_brookesia::systems::phone
