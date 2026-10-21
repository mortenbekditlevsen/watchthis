/*
 * SPDX-License-Identifier: CC0-1.0
 */
#ifndef __FILE_STORE_H__
#define __FILE_STORE_H__

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* User files (photos, later music) on the LittleFS `store` partition, mounted at FILE_STORE_ROOT. Each kind has its
 * own directory; a file's id is its name without extension. Thread-safe. */

#define FILE_STORE_ROOT    "/store"
#define FILE_STORE_ID_MAX  32       /* Including the terminating NUL */
#define FILE_STORE_PATH_MAX 64
#define FILE_STORE_NAME_MAX 64      /* Display name (UTF-8), including the terminating NUL */

typedef enum {
    FILE_STORE_PHOTO = 0,   /* <root>/photos/<id>.jpg */
    FILE_STORE_MUSIC,       /* <root>/music/<id>.mp3 */
    FILE_STORE_FACE,        /* <root>/faces/<id>.wf: a watch face (components/watch_faces) */
    FILE_STORE_FACE_ASSET,  /* <root>/assets/<id>.ast: PNG/JPEG background or LVGL binfont used by faces */
    FILE_STORE_KIND_MAX,
} file_store_kind_t;

typedef struct {
    char id[FILE_STORE_ID_MAX];
    char name[FILE_STORE_NAME_MAX];     /* Display name given at upload; empty if none */
    uint32_t size;
} file_store_entry_t;

typedef enum {
    FILE_STORE_OK = 0,
    FILE_STORE_ERR_FAILED,      /* I/O error */
    FILE_STORE_ERR_INVALID,     /* Bad kind/id/size, or no upload in progress */
    FILE_STORE_ERR_NO_SPACE,
    FILE_STORE_ERR_BUSY,        /* Another upload is in progress */
    FILE_STORE_ERR_CHECK,       /* Size, CRC or file format doesn't match */
    FILE_STORE_ERR_NOT_FOUND,
} file_store_err_t;

/* Extra check of an upload at commit (after size, CRC and magic bytes passed); `path` is the complete temporary file.
 * Called with the store locked: don't call other file_store functions from it. */
typedef bool (*file_store_check_cb_t)(file_store_kind_t kind, const char *path);
/* A file was stored (committed) or removed. Called with the store locked from the uploading task: keep it short. */
typedef void (*file_store_change_cb_t)(file_store_kind_t kind, const char *id, bool removed);

/* One of each; for kinds that need more than a magic-bytes check, and to notice new files (watch faces) */
void file_store_set_hooks(file_store_check_cb_t check, file_store_change_cb_t changed);

/* Mount the partition (once; later calls just return the result). Formats it if it can't be mounted. */
bool file_store_mount(void);

/* Fill `entries` (up to `max`) with the files of `kind`, sorted by id. Returns how many there are in total (may be
 * more than `max`), or -1 on error. */
int file_store_list(file_store_kind_t kind, file_store_entry_t *entries, int max);

/* Full path of a file, for fopen(). */
bool file_store_path(file_store_kind_t kind, const char *id, char *path, size_t path_len);

/* Partition usage in bytes. */
bool file_store_usage(size_t *total, size_t *used);

/* Valid ids: 1..FILE_STORE_ID_MAX-1 characters from [A-Za-z0-9_-]. */
bool file_store_id_valid(const char *id);

/* Upload (one at a time): data goes to a temporary file and only becomes visible after a successful commit (size,
 * CRC-32 (IEEE, as zlib's crc32) and file format checked). Uploading an existing id replaces it on commit. */
file_store_err_t file_store_upload_begin(file_store_kind_t kind, const char *id, const char *name, uint32_t size,
                                         uint32_t crc32);
/* Data must arrive in order: `offset` == bytes received so far. */
file_store_err_t file_store_upload_write(uint32_t offset, const void *data, size_t len);
file_store_err_t file_store_upload_commit(void);
void file_store_upload_abort(void);
/* Progress of the upload in progress; false if none. */
bool file_store_upload_progress(uint32_t *received, uint32_t *size);

file_store_err_t file_store_remove(file_store_kind_t kind, const char *id);

#ifdef __cplusplus
}
#endif

#endif
