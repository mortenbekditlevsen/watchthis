/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include <cstdio>
#include <cstring>
#include "lvgl.h"
#include "src/draw/lv_image_decoder_private.h"  // Writing a decoder needs the descriptor's fields
// LVGL's own TJPGD. Its jd_prepare/jd_decomp are renamed in main/CMakeLists.txt so they don't resolve to the
// incompatible copies in the ESP32-C6 ROM; use the same names here.
#define jd_prepare lv_tjpgd_jd_prepare
#define jd_decomp lv_tjpgd_jd_decomp
#include "src/libs/tjpgd/tjpgd.h"
#include "cats_jpeg_decoder.hpp"

namespace {

constexpr size_t TJPGD_POOL_SIZE = 4096;    // Same as LVGL's TJPGD decoder

constexpr size_t PATH_MAX_LEN = 64;

struct Session {
    // Input stream
    char path[PATH_MAX_LEN] = "";
    FILE *file = nullptr;
    // Decoder state
    JDEC jd = {};
    uint8_t *pool = nullptr;
    bool valid = false;
    int32_t mcu_w = 0;
    int32_t mcu_h = 0;
    int32_t next_row = 0;       // First image row of the next MCU row to decode
    // Last decoded MCU row, full image width
    lv_draw_buf_t *rows = nullptr;
    int32_t rows_alloc_h = 0;   // Height rows was allocated with (its header.h is set per MCU row served)
    int32_t rows_y = -1;        // Image row where it starts, -1 if empty
};

// Image sources handed out by cats_jpeg_decoder_make_src(): lv_image_dsc_t::data points at one of these
struct Source {
    char path[PATH_MAX_LEN];
};
Source sources[2];
int next_source = 0;

lv_image_decoder_t *decoder = nullptr;
Session session;

size_t input_func(JDEC *jd, uint8_t *buff, size_t ndata)
{
    Session *s = static_cast<Session *>(jd->device);
    if (buff != nullptr) {
        return fread(buff, 1, ndata, s->file);
    }
    return (fseek(s->file, ndata, SEEK_CUR) == 0) ? ndata : 0;
}

void session_close_file(void)
{
    Session &s = session;
    if (s.file != nullptr) {
        fclose(s.file);
        s.file = nullptr;
    }
    s.path[0] = '\0';
    s.valid = false;
}

// (Re)start decoding `path` from the top
bool session_start(const char *path)
{
    Session &s = session;

    s.valid = false;
    if ((s.file != nullptr) && (strcmp(s.path, path) == 0)) {
        rewind(s.file);
    } else {
        session_close_file();
        s.file = fopen(path, "rb");
        if (s.file == nullptr) {
            return false;
        }
        strlcpy(s.path, path, sizeof(s.path));
    }
    if (s.pool == nullptr) {
        s.pool = static_cast<uint8_t *>(lv_malloc(TJPGD_POOL_SIZE));
        if (s.pool == nullptr) {
            return false;
        }
    }
    if (jd_prepare(&s.jd, input_func, s.pool, TJPGD_POOL_SIZE, &s) != JDR_OK) {
        return false;
    }
    // Same initialization as LVGL's TJPGD decoder before decoding MCUs one by one
    s.jd.scale = 0;
    s.jd.dcv[2] = s.jd.dcv[1] = s.jd.dcv[0] = 0;
    s.jd.rst = 0;
    s.jd.rsc = 0;
    s.mcu_w = s.jd.msx * 8;
    s.mcu_h = s.jd.msy * 8;

    if ((s.rows != nullptr) && ((s.rows->header.w != s.jd.width) || (s.rows_alloc_h != s.mcu_h))) {
        s.rows->header.h = s.rows_alloc_h;
        lv_draw_buf_destroy(s.rows);
        s.rows = nullptr;
    }
    if (s.rows == nullptr) {
        s.rows = lv_draw_buf_create(s.jd.width, s.mcu_h, LV_COLOR_FORMAT_RGB565, LV_STRIDE_AUTO);
        if (s.rows == nullptr) {
            return false;
        }
        s.rows_alloc_h = s.mcu_h;
    }
    s.next_row = 0;
    s.rows_y = -1;
    s.valid = true;

    return true;
}

// Decode the MCU row at s.next_row; convert it into s.rows (RGB565) if `output`, otherwise just advance
bool session_decode_row(bool output)
{
    Session &s = session;
    JDEC &jd = s.jd;
    const int32_t y = s.next_row;

    for (int32_t x = 0; x < jd.width; x += s.mcu_w) {
        if (jd.nrst && (jd.rst++ == jd.nrst)) {
            if (jd_restart(&jd, jd.rsc++) != JDR_OK) {
                return false;
            }
            jd.rst = 1;
        }
        if (jd_mcu_load(&jd) != JDR_OK) {
            return false;
        }
        if (!output) {
            continue;
        }
        if (jd_mcu_output(&jd, nullptr, x, y) != JDR_OK) {
            return false;
        }
        // jd_mcu_output leaves the visible part of the MCU in jd.workbuf (rx x ry), 3 bytes per pixel in LVGL's
        // RGB888 memory order: B, G, R
        const int32_t rx = LV_MIN(s.mcu_w, jd.width - x);
        const int32_t ry = LV_MIN(s.mcu_h, jd.height - y);
        const uint8_t *src = static_cast<const uint8_t *>(jd.workbuf);
        for (int32_t iy = 0; iy < ry; iy++) {
            uint16_t *dst = reinterpret_cast<uint16_t *>(s.rows->data + iy * s.rows->header.stride) + x;
            for (int32_t ix = 0; ix < rx; ix++, src += 3) {
                dst[ix] = ((src[2] & 0xF8) << 8) | ((src[1] & 0xFC) << 3) | (src[0] >> 3);
            }
        }
    }
    if (output) {
        s.rows_y = y;
    }
    s.next_row += s.mcu_h;

    return true;
}

// Make s.rows hold the MCU row starting at image row `y` (a multiple of the MCU height)
bool session_seek_row(int32_t y)
{
    Session &s = session;

    if (s.rows_y == y) {
        return true;
    }
    if (y < s.next_row) {
        // JPEG can only be decoded forward: start over
        if (!session_start(s.path)) {
            return false;
        }
    }
    while (s.next_row < y) {
        if (!session_decode_row(false)) {
            s.valid = false;
            return false;
        }
    }
    if (!session_decode_row(true)) {
        s.valid = false;
        return false;
    }

    return true;
}

const char *source_path(const lv_image_decoder_dsc_t *dsc)
{
    if (dsc->src_type != LV_IMAGE_SRC_VARIABLE) {
        return nullptr;
    }
    const lv_image_dsc_t *img = static_cast<const lv_image_dsc_t *>(dsc->src);
    const Source *src = reinterpret_cast<const Source *>(img->data);
    if ((src < &sources[0]) || (src >= &sources[2])) {
        return nullptr;
    }
    return src->path;
}

// Make the session decode `path`, keeping its position if it already does
bool session_use(const char *path)
{
    if (session.valid && (strcmp(session.path, path) == 0)) {
        return true;
    }
    return session_start(path);
}

lv_result_t decoder_info(lv_image_decoder_t *dec, lv_image_decoder_dsc_t *dsc, lv_image_header_t *header)
{
    LV_UNUSED(dec);
    const char *path = source_path(dsc);
    if ((path == nullptr) || !session_use(path)) {
        return LV_RESULT_INVALID;
    }
    // The real size from the JPEG header; LVGL centers/clips it in the image widget
    header->cf = LV_COLOR_FORMAT_RGB565;
    header->w = session.jd.width;
    header->h = session.jd.height;
    header->stride = session.jd.width * 2;

    return LV_RESULT_OK;
}

lv_result_t decoder_open(lv_image_decoder_t *dec, lv_image_decoder_dsc_t *dsc)
{
    LV_UNUSED(dec);
    const char *path = source_path(dsc);
    if ((path == nullptr) || !session_use(path)) {
        return LV_RESULT_INVALID;
    }
    // No full image: LVGL draws it piece by piece through decoder_get_area()
    dsc->decoded = nullptr;

    return LV_RESULT_OK;
}

lv_result_t decoder_get_area(lv_image_decoder_t *dec, lv_image_decoder_dsc_t *dsc, const lv_area_t *full_area,
                             lv_area_t *decoded_area)
{
    LV_UNUSED(dec);
    Session &s = session;
    if (!s.valid) {
        return LV_RESULT_INVALID;
    }

    // Serve whole MCU rows covering the requested area (image-relative), top to bottom, then stop
    int32_t y;
    if (decoded_area->y1 == LV_COORD_MIN) {
        y = (LV_MAX(full_area->y1, 0) / s.mcu_h) * s.mcu_h;
    } else {
        y = decoded_area->y1 + s.mcu_h;
    }
    if ((y > full_area->y2) || (y >= s.jd.height) || !session_seek_row(y)) {
        return LV_RESULT_INVALID;
    }

    const int32_t h = LV_MIN(s.mcu_h, s.jd.height - y);
    s.rows->header.h = h;
    decoded_area->x1 = 0;
    decoded_area->x2 = s.jd.width - 1;
    decoded_area->y1 = y;
    decoded_area->y2 = y + h - 1;
    dsc->decoded = s.rows;

    return LV_RESULT_OK;
}

void decoder_close(lv_image_decoder_t *dec, lv_image_decoder_dsc_t *dsc)
{
    LV_UNUSED(dec);
    // The session (and its row buffer) outlives the draw; see cats_jpeg_decoder_release()
    dsc->decoded = nullptr;
}

} // namespace

void cats_jpeg_decoder_init(void)
{
    if (decoder == nullptr) {
        // Newest decoders are tried first, so this runs before LVGL's TJPGD decoder
        decoder = lv_image_decoder_create();
        lv_image_decoder_set_info_cb(decoder, decoder_info);
        lv_image_decoder_set_open_cb(decoder, decoder_open);
        lv_image_decoder_set_get_area_cb(decoder, decoder_get_area);
        lv_image_decoder_set_close_cb(decoder, decoder_close);
    }
}

void cats_jpeg_decoder_make_src(lv_image_dsc_t *dsc, const char *path)
{
    Source &src = sources[next_source];
    next_source ^= 1;
    strlcpy(src.path, path, sizeof(src.path));

    memset(dsc, 0, sizeof(*dsc));
    dsc->header.magic = LV_IMAGE_HEADER_MAGIC;
    dsc->header.cf = LV_COLOR_FORMAT_RAW;  // Real format/size come from decoder_info()
    dsc->data = reinterpret_cast<const uint8_t *>(&src);
    dsc->data_size = sizeof(src);
}

void cats_jpeg_decoder_release(void)
{
    session_close_file();
    if (session.rows != nullptr) {
        // Restore the allocated height before handing the buffer back
        session.rows->header.h = session.rows_alloc_h;
        lv_draw_buf_destroy(session.rows);
    }
    lv_free(session.pool);
    session = Session();
}
