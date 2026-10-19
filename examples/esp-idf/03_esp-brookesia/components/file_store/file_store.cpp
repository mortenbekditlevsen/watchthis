/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>
#include "esp_littlefs.h"
#include "esp_rom_crc.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "file_store.h"

static const char *TAG = "FileStore";

static constexpr const char *PARTITION_LABEL = "store";

static const char *const KIND_DIR[FILE_STORE_KIND_MAX] = {"photos", "music"};
static const char *const KIND_EXT[FILE_STORE_KIND_MAX] = {".jpg", ".mp3"};
static constexpr const char *NAME_EXT = ".nm";      // Sidecar with the display name
static constexpr const char *PART_EXT = ".part";    // Upload in progress
static constexpr size_t SPACE_MARGIN = 64 * 1024;   // Keep LittleFS some room for metadata
static constexpr size_t UPLOAD_BUFFER_SIZE = 4096;  // Batch the small BLE chunks into bigger flash writes

static SemaphoreHandle_t lock = nullptr;
static bool mounted = false;

struct Upload {
    FILE *file = nullptr;
    char *buffer = nullptr;
    file_store_kind_t kind = FILE_STORE_PHOTO;
    char id[FILE_STORE_ID_MAX] = "";
    char name[FILE_STORE_NAME_MAX] = "";
    uint32_t size = 0;
    uint32_t crc32 = 0;
    uint32_t received = 0;
    uint32_t running_crc = 0;
    uint8_t head[4] = {};       // First bytes, for the format check
};
static Upload upload;

namespace {

struct Guard {
    Guard()
    {
        xSemaphoreTakeRecursive(lock, portMAX_DELAY);
    }
    ~Guard()
    {
        xSemaphoreGiveRecursive(lock);
    }
};

bool valid_kind(file_store_kind_t kind)
{
    return (kind >= 0) && (kind < FILE_STORE_KIND_MAX);
}

} // namespace

bool file_store_mount(void)
{
    static StaticSemaphore_t lock_buf;
    if (lock == nullptr) {
        // First call happens from app_main/LVGL before any concurrent user exists
        lock = xSemaphoreCreateRecursiveMutexStatic(&lock_buf);
    }
    Guard guard;

    if (mounted) {
        return true;
    }

    esp_vfs_littlefs_conf_t conf = {};
    conf.base_path = FILE_STORE_ROOT;
    conf.partition_label = PARTITION_LABEL;
    conf.format_if_mount_failed = true;
    esp_err_t ret = esp_vfs_littlefs_register(&conf);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Mount '%s' failed: %s", PARTITION_LABEL, esp_err_to_name(ret));
        return false;
    }

    for (int kind = 0; kind < FILE_STORE_KIND_MAX; kind++) {
        char dir[FILE_STORE_PATH_MAX];
        snprintf(dir, sizeof(dir), "%s/%s", FILE_STORE_ROOT, KIND_DIR[kind]);
        mkdir(dir, 0775);   // Fails harmlessly if it exists
    }

    size_t total = 0, used = 0;
    esp_littlefs_info(PARTITION_LABEL, &total, &used);
    ESP_LOGI(TAG, "Mounted %s: %u of %u KB used", FILE_STORE_ROOT, (unsigned)(used / 1024), (unsigned)(total / 1024));
    mounted = true;

    return true;
}

int file_store_list(file_store_kind_t kind, file_store_entry_t *entries, int max)
{
    if (!valid_kind(kind) || !file_store_mount()) {
        return -1;
    }
    Guard guard;

    char dir_path[FILE_STORE_PATH_MAX];
    snprintf(dir_path, sizeof(dir_path), "%s/%s", FILE_STORE_ROOT, KIND_DIR[kind]);
    DIR *dir = opendir(dir_path);
    if (dir == nullptr) {
        return -1;
    }

    const char *ext = KIND_EXT[kind];
    const size_t ext_len = strlen(ext);
    int count = 0;
    struct dirent *de;
    while ((de = readdir(dir)) != nullptr) {
        const size_t len = strlen(de->d_name);
        if ((len <= ext_len) || (len - ext_len >= FILE_STORE_ID_MAX) || strcmp(de->d_name + len - ext_len, ext)) {
            continue;   // Not ours (or a temp file from an interrupted upload)
        }
        if (count < max) {
            file_store_entry_t &e = entries[count];
            memcpy(e.id, de->d_name, len - ext_len);
            e.id[len - ext_len] = '\0';
            char path[FILE_STORE_PATH_MAX + sizeof(de->d_name)];   // Room for any entry name
            struct stat st;
            snprintf(path, sizeof(path), "%s/%s", dir_path, de->d_name);
            e.size = (stat(path, &st) == 0) ? st.st_size : 0;
            e.name[0] = '\0';
            snprintf(path, sizeof(path), "%s/%s%s", dir_path, e.id, NAME_EXT);
            FILE *nf = fopen(path, "r");
            if (nf != nullptr) {
                const size_t n = fread(e.name, 1, sizeof(e.name) - 1, nf);
                e.name[n] = '\0';
                fclose(nf);
            }
        }
        count++;
    }
    closedir(dir);

    std::sort(entries, entries + std::min(count, max), [](const file_store_entry_t &a, const file_store_entry_t &b) {
        return strcmp(a.id, b.id) < 0;
    });

    return count;
}

bool file_store_path(file_store_kind_t kind, const char *id, char *path, size_t path_len)
{
    if (!valid_kind(kind) || (id == nullptr)) {
        return false;
    }
    const int n = snprintf(path, path_len, "%s/%s/%s%s", FILE_STORE_ROOT, KIND_DIR[kind], id, KIND_EXT[kind]);
    return (n > 0) && ((size_t)n < path_len);
}

bool file_store_usage(size_t *total, size_t *used)
{
    if (!file_store_mount()) {
        return false;
    }
    Guard guard;
    return esp_littlefs_info(PARTITION_LABEL, total, used) == ESP_OK;
}

bool file_store_id_valid(const char *id)
{
    if ((id == nullptr) || (id[0] == '\0') || (strlen(id) >= FILE_STORE_ID_MAX)) {
        return false;
    }
    for (const char *p = id; *p; p++) {
        if (!(((*p >= 'a') && (*p <= 'z')) || ((*p >= 'A') && (*p <= 'Z')) || ((*p >= '0') && (*p <= '9')) ||
                (*p == '_') || (*p == '-'))) {
            return false;
        }
    }
    return true;
}

namespace {

void part_path(char *path, size_t len)
{
    snprintf(path, len, "%s/%s/%s%s", FILE_STORE_ROOT, KIND_DIR[upload.kind], upload.id, PART_EXT);
}

void upload_close(bool remove_part)
{
    if (upload.file != nullptr) {
        fclose(upload.file);
        upload.file = nullptr;
    }
    free(upload.buffer);
    upload.buffer = nullptr;
    if (remove_part) {
        char path[FILE_STORE_PATH_MAX];
        part_path(path, sizeof(path));
        unlink(path);
    }
    upload.id[0] = '\0';
}

bool format_ok(file_store_kind_t kind, const uint8_t head[4], uint32_t size)
{
    if (size < 4) {
        return false;
    }
    switch (kind) {
    case FILE_STORE_PHOTO:
        return (head[0] == 0xFF) && (head[1] == 0xD8);     // JPEG SOI
    case FILE_STORE_MUSIC:
        return ((head[0] == 'I') && (head[1] == 'D') && (head[2] == '3')) ||   // ID3 tag
               ((head[0] == 0xFF) && ((head[1] & 0xE0) == 0xE0));             // MPEG frame sync
    default:
        return false;
    }
}

} // namespace

file_store_err_t file_store_upload_begin(file_store_kind_t kind, const char *id, const char *name, uint32_t size,
                                         uint32_t crc32)
{
    if (!valid_kind(kind) || !file_store_id_valid(id) || (size == 0)) {
        return FILE_STORE_ERR_INVALID;
    }
    if (!file_store_mount()) {
        return FILE_STORE_ERR_FAILED;
    }
    Guard guard;

    if (upload.file != nullptr) {
        return FILE_STORE_ERR_BUSY;
    }
    size_t total = 0, used = 0;
    if ((esp_littlefs_info(PARTITION_LABEL, &total, &used) != ESP_OK) || (used + size + SPACE_MARGIN > total)) {
        return FILE_STORE_ERR_NO_SPACE;
    }

    upload = Upload();
    upload.kind = kind;
    strlcpy(upload.id, id, sizeof(upload.id));
    strlcpy(upload.name, (name != nullptr) ? name : "", sizeof(upload.name));
    upload.size = size;
    upload.crc32 = crc32;

    char path[FILE_STORE_PATH_MAX];
    part_path(path, sizeof(path));
    upload.file = fopen(path, "wb");
    if (upload.file == nullptr) {
        upload.id[0] = '\0';
        return FILE_STORE_ERR_FAILED;
    }
    upload.buffer = static_cast<char *>(malloc(UPLOAD_BUFFER_SIZE));
    if (upload.buffer != nullptr) {
        setvbuf(upload.file, upload.buffer, _IOFBF, UPLOAD_BUFFER_SIZE);
    }
    ESP_LOGI(TAG, "Upload %s/%s (%u bytes)", KIND_DIR[kind], id, (unsigned)size);

    return FILE_STORE_OK;
}

file_store_err_t file_store_upload_write(uint32_t offset, const void *data, size_t len)
{
    Guard guard;

    if (upload.file == nullptr) {
        return FILE_STORE_ERR_INVALID;
    }
    if ((offset != upload.received) || (upload.received + len > upload.size)) {
        return FILE_STORE_ERR_INVALID;
    }
    if (fwrite(data, 1, len, upload.file) != len) {
        upload_close(true);
        return FILE_STORE_ERR_FAILED;
    }
    const uint8_t *bytes = static_cast<const uint8_t *>(data);
    for (size_t i = 0; (upload.received + i < sizeof(upload.head)) && (i < len); i++) {
        upload.head[upload.received + i] = bytes[i];
    }
    upload.running_crc = esp_rom_crc32_le(upload.running_crc, bytes, len);
    upload.received += len;

    return FILE_STORE_OK;
}

file_store_err_t file_store_upload_commit(void)
{
    Guard guard;

    if (upload.file == nullptr) {
        return FILE_STORE_ERR_INVALID;
    }
    if ((upload.received != upload.size) || (upload.running_crc != upload.crc32) ||
            !format_ok(upload.kind, upload.head, upload.size)) {
        ESP_LOGW(TAG, "Upload %s rejected (%u/%u bytes, crc %08x/%08x)", upload.id, (unsigned)upload.received,
                 (unsigned)upload.size, (unsigned)upload.running_crc, (unsigned)upload.crc32);
        upload_close(true);
        return FILE_STORE_ERR_CHECK;
    }
    if (fclose(upload.file) != 0) {
        upload.file = nullptr;
        upload_close(true);
        return FILE_STORE_ERR_FAILED;
    }
    upload.file = nullptr;

    char part[FILE_STORE_PATH_MAX], final_path[FILE_STORE_PATH_MAX], name_path[FILE_STORE_PATH_MAX + 4];
    part_path(part, sizeof(part));
    file_store_path(upload.kind, upload.id, final_path, sizeof(final_path));
    snprintf(name_path, sizeof(name_path), "%s/%s/%s%s", FILE_STORE_ROOT, KIND_DIR[upload.kind], upload.id, NAME_EXT);
    unlink(final_path);
    unlink(name_path);
    if (rename(part, final_path) != 0) {
        upload_close(true);
        return FILE_STORE_ERR_FAILED;
    }
    if (upload.name[0] != '\0') {
        FILE *nf = fopen(name_path, "w");
        if (nf != nullptr) {
            fputs(upload.name, nf);
            fclose(nf);
        }
    }
    ESP_LOGI(TAG, "Stored %s/%s", KIND_DIR[upload.kind], upload.id);
    upload_close(false);

    return FILE_STORE_OK;
}

void file_store_upload_abort(void)
{
    Guard guard;
    if (upload.file != nullptr) {
        upload_close(true);
    }
}

bool file_store_upload_progress(uint32_t *received, uint32_t *size)
{
    // Lock-free read for UI polling; values may be momentarily inconsistent
    if (upload.file == nullptr) {
        return false;
    }
    *received = upload.received;
    *size = upload.size;
    return true;
}

file_store_err_t file_store_remove(file_store_kind_t kind, const char *id)
{
    if (!valid_kind(kind) || !file_store_id_valid(id)) {
        return FILE_STORE_ERR_INVALID;
    }
    if (!file_store_mount()) {
        return FILE_STORE_ERR_FAILED;
    }
    Guard guard;

    char path[FILE_STORE_PATH_MAX], name_path[FILE_STORE_PATH_MAX + 4];
    file_store_path(kind, id, path, sizeof(path));
    snprintf(name_path, sizeof(name_path), "%s/%s/%s%s", FILE_STORE_ROOT, KIND_DIR[kind], id, NAME_EXT);
    if (unlink(path) != 0) {
        return FILE_STORE_ERR_NOT_FOUND;
    }
    unlink(name_path);
    ESP_LOGI(TAG, "Removed %s/%s", KIND_DIR[kind], id);

    return FILE_STORE_OK;
}
