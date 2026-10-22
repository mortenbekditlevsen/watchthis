#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "esp_timer.h"

// LVGL is configured through Kconfig (CONFIG_LV_CONF_SKIP); these mirror what LVGL's CMake passes to C code, since
// swiftc does not forward -D definitions to the Clang importer
#ifndef ESP_PLATFORM
#define ESP_PLATFORM 1
#endif
#define LV_CONF_INCLUDE_SIMPLE 1
#include "lvgl.h"
#include "tools_shim.h"

#include "music_player.h"
#include "include/watch_tools.h"
