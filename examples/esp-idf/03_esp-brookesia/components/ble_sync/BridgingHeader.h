#include <stdio.h>
#include <math.h>
#include <stdlib.h>

#ifndef MYNEWT_VAL_BLE_GATT_CSFC_SIZE
#define MYNEWT_VAL_BLE_GATT_CSFC_SIZE 0
#endif

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "sdkconfig.h"
#include "esp_err.h"

#include "nimble/ble.h"
#include "nimble/transport.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "host/ble_gap.h"
#include "host/ble_gatt.h"
#include "host/ble_hs_mbuf.h"
#include "host/util/util.h"
#include "os/os_mbuf.h"
#include "esp_nimble_cfg.h"
#include "esp_bt.h"

#include "pairing.h"
#include "include/ble_sync.h"
#include "file_store.h"

#ifndef MYNEWT_VAL_BLE_LL_WHITELIST_SIZE
#define MYNEWT_VAL_BLE_LL_WHITELIST_SIZE CONFIG_BT_NIMBLE_WHITELIST_SIZE
#endif

// A mutex for the C API (start/stop/background can come from different tasks); macros wrapped for Swift
#ifndef BLE_SYNC_MUTEX_SHIM
#define BLE_SYNC_MUTEX_SHIM
#include "freertos/semphr.h"
#include "esp_timer.h"
static inline SemaphoreHandle_t ble_sync_mutex_create(void) { return xSemaphoreCreateMutex(); }
static inline void ble_sync_mutex_take(SemaphoreHandle_t m) { xSemaphoreTake(m, portMAX_DELAY); }
static inline void ble_sync_mutex_give(SemaphoreHandle_t m) { xSemaphoreGive(m); }
#endif
