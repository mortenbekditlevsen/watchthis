#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include <dirent.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_heap_caps.h"

// LVGL is configured through Kconfig (CONFIG_LV_CONF_SKIP); these mirror what LVGL's CMake passes to C code, since
// swiftc does not forward -D definitions to the Clang importer
#ifndef ESP_PLATFORM
#define ESP_PLATFORM 1
#endif
#define LV_CONF_INCLUDE_SIMPLE 1
#include "lvgl.h"
#include "lv_shim.h"

// LVGL's own TJPGD. Its jd_prepare/jd_decomp are renamed in main/CMakeLists.txt so they don't resolve to the
// ESP32-C6 ROM's incompatible copies; use the renamed ones here too
#define jd_prepare lv_tjpgd_jd_prepare
#define jd_decomp lv_tjpgd_jd_decomp
#include "src/libs/tjpgd/tjpgd.h"

// Inflate (zlib) for PNG backgrounds: the ROM's miniz
#include "miniz.h"

#include "file_store.h"
#include "step_counter.h"
#include "include/watch_faces.h"
