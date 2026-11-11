/*******************************************************************************
 * Size: 12 px
 * Bpp: 4
 * Opts: --font lvgl/scripts/built_in_font/Montserrat-Medium.ttf -r 0xC5,0xC6,0xD8,0xE5,0xE6,0xF8 --size 12 --bpp 4
 *       --no-compress --no-prefilter --format lvgl --lv-font-name watch_font_danish_12 --lv-fallback lv_font_montserrat_12
 *       (lv_font_conv 1.5.3)
 *
 * Danish letters (ÆØÅæøå) only; all other glyphs come from the fallback lv_font_montserrat_12.
 * line_height/base_line are copied from lv_font_montserrat_12 so mixed text shares one baseline.
 ******************************************************************************/

#include "lvgl.h"

#ifndef WATCH_FONT_DANISH_12
#define WATCH_FONT_DANISH_12 1
#endif

#if WATCH_FONT_DANISH_12

/*-----------------
 *    BITMAPS
 *----------------*/

/*Store the image of the glyphs*/
static LV_ATTRIBUTE_LARGE_CONST const uint8_t glyph_bitmap[] = {
    /* U+00C5 "Å" */
    0x0, 0x0, 0x69, 0x30, 0x0, 0x0, 0x0, 0x90,
    0x90, 0x0, 0x0, 0x0, 0x59, 0x30, 0x0, 0x0,
    0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x6f, 0x30,
    0x0, 0x0, 0x0, 0xdd, 0x90, 0x0, 0x0, 0x4,
    0xe3, 0xf1, 0x0, 0x0, 0xb, 0x80, 0xc7, 0x0,
    0x0, 0x1f, 0x20, 0x6e, 0x0, 0x0, 0x8c, 0x0,
    0x1f, 0x50, 0x0, 0xef, 0xee, 0xef, 0xb0, 0x6,
    0xe2, 0x11, 0x14, 0xf2, 0xc, 0x70, 0x0, 0x0,
    0xb9,

    /* U+00C6 "Æ" */
    0x0, 0x0, 0x4, 0xff, 0xff, 0xff, 0xb0, 0x0,
    0x0, 0xd9, 0xf2, 0x22, 0x21, 0x0, 0x0, 0x6d,
    0x3f, 0x0, 0x0, 0x0, 0x0, 0xe, 0x53, 0xf0,
    0x0, 0x0, 0x0, 0x8, 0xd0, 0x3f, 0xff, 0xff,
    0x30, 0x1, 0xf5, 0x3, 0xf2, 0x22, 0x20, 0x0,
    0xaf, 0xee, 0xff, 0x0, 0x0, 0x0, 0x3f, 0x41,
    0x14, 0xf2, 0x22, 0x22, 0xb, 0x80, 0x0, 0x3f,
    0xff, 0xff, 0xe0,

    /* U+00D8 "Ø" */
    0x0, 0x0, 0x0, 0x2, 0xc0, 0x0, 0x3b, 0xef,
    0xbf, 0x20, 0x5, 0xf9, 0x33, 0xff, 0x60, 0xe,
    0x60, 0x2, 0xc5, 0xf1, 0x4e, 0x0, 0xb, 0x30,
    0xd5, 0x6c, 0x0, 0x68, 0x0, 0xb7, 0x4e, 0x1,
    0xc0, 0x0, 0xd5, 0xe, 0x6b, 0x30, 0x5, 0xf1,
    0x5, 0xff, 0x33, 0x8f, 0x60, 0x1, 0xfc, 0xef,
    0xb4, 0x0, 0xb, 0x30, 0x0, 0x0, 0x0,

    /* U+00E5 "å" */
    0x0, 0x49, 0x40, 0x0, 0x9, 0x9, 0x0, 0x0,
    0x49, 0x40, 0x0, 0x0, 0x0, 0x0, 0x8, 0xdf,
    0xc3, 0x0, 0xa4, 0x29, 0xd0, 0x0, 0x0, 0x1f,
    0x10, 0x8d, 0xee, 0xf2, 0x4e, 0x10, 0xf, 0x24,
    0xe0, 0x7, 0xf2, 0x9, 0xed, 0x8f, 0x20,

    /* U+00E6 "æ" */
    0x8, 0xdf, 0xc3, 0x6e, 0xfa, 0x10, 0xa, 0x42,
    0x9f, 0xe4, 0x2a, 0xc0, 0x0, 0x0, 0x1f, 0x50,
    0x0, 0xe3, 0x8, 0xde, 0xef, 0xee, 0xee, 0xe5,
    0x4d, 0x0, 0xf, 0x50, 0x0, 0x0, 0x4e, 0x32,
    0x9e, 0xe4, 0x26, 0x80, 0x8, 0xef, 0xa1, 0x7e,
    0xfd, 0x30,

    /* U+00F8 "ø" */
    0x0, 0x0, 0x3, 0x70, 0x2, 0xbf, 0xef, 0x0,
    0xe, 0xa2, 0x9f, 0x80, 0x5d, 0x0, 0xa4, 0xf0,
    0x7b, 0x8, 0x21, 0xf1, 0x5d, 0x28, 0x4, 0xf0,
    0xd, 0xf3, 0x3e, 0x80, 0x7, 0xff, 0xe8, 0x0,
    0xa, 0x0, 0x0, 0x0
};


/*---------------------
 *  GLYPH DESCRIPTION
 *--------------------*/

static const lv_font_fmt_txt_glyph_dsc_t glyph_dsc[] = {
    {.bitmap_index = 0, .adv_w = 0, .box_w = 0, .box_h = 0, .ofs_x = 0, .ofs_y = 0} /* id = 0 reserved */,
    {.bitmap_index = 0, .adv_w = 141, .box_w = 10, .box_h = 13, .ofs_x = -1, .ofs_y = 0},
    {.bitmap_index = 65, .adv_w = 201, .box_w = 13, .box_h = 9, .ofs_x = -1, .ofs_y = 0},
    {.bitmap_index = 124, .adv_w = 161, .box_w = 10, .box_h = 11, .ofs_x = 0, .ofs_y = -1},
    {.bitmap_index = 179, .adv_w = 115, .box_w = 7, .box_h = 11, .ofs_x = 0, .ofs_y = 0},
    {.bitmap_index = 218, .adv_w = 190, .box_w = 12, .box_h = 7, .ofs_x = 0, .ofs_y = 0},
    {.bitmap_index = 260, .adv_w = 122, .box_w = 8, .box_h = 9, .ofs_x = 0, .ofs_y = -1}
};

/*---------------------
 *  CHARACTER MAPPING
 *--------------------*/

static const uint16_t unicode_list_0[] = {
    0x0, 0x1, 0x13, 0x20, 0x21, 0x33
};

/*Collect the unicode lists and glyph_id offsets*/
static const lv_font_fmt_txt_cmap_t cmaps[] =
{
    {
        .range_start = 197, .range_length = 52, .glyph_id_start = 1,
        .unicode_list = unicode_list_0, .glyph_id_ofs_list = NULL, .list_length = 6, .type = LV_FONT_FMT_TXT_CMAP_SPARSE_TINY
    }
};

/*-----------------
 *    KERNING
 *----------------*/


/*Map glyph_ids to kern left classes*/
static const uint8_t kern_left_class_mapping[] =
{
    0, 1, 2, 3, 4, 5, 6
};

/*Map glyph_ids to kern right classes*/
static const uint8_t kern_right_class_mapping[] =
{
    0, 1, 1, 2, 3, 3, 4
};

/*Kern values between classes*/
static const int8_t kern_class_values[] =
{
    2, -2, 0, -1, 0, -1, -1, -1,
    -2, 0, 0, 0, 0, 0, 0, 1,
    0, 0, -3, 0, -2, 0, -1, 0
};


/*Collect the kern class' data in one place*/
static const lv_font_fmt_txt_kern_classes_t kern_classes =
{
    .class_pair_values   = kern_class_values,
    .left_class_mapping  = kern_left_class_mapping,
    .right_class_mapping = kern_right_class_mapping,
    .left_class_cnt      = 6,
    .right_class_cnt     = 4,
};

/*--------------------
 *  ALL CUSTOM DATA
 *--------------------*/

#if LVGL_VERSION_MAJOR == 8
/*Store all the custom data of the font*/
static  lv_font_fmt_txt_glyph_cache_t cache;
#endif

#if LVGL_VERSION_MAJOR >= 8
static const lv_font_fmt_txt_dsc_t font_dsc = {
#else
static lv_font_fmt_txt_dsc_t font_dsc = {
#endif
    .glyph_bitmap = glyph_bitmap,
    .glyph_dsc = glyph_dsc,
    .cmaps = cmaps,
    .kern_dsc = &kern_classes,
    .kern_scale = 16,
    .cmap_num = 1,
    .bpp = 4,
    .kern_classes = 1,
    .bitmap_format = 0,
#if LVGL_VERSION_MAJOR == 8
    .cache = &cache
#endif
};

extern const lv_font_t lv_font_montserrat_12;


/*-----------------
 *  PUBLIC FONT
 *----------------*/

/*Initialize a public general font descriptor*/
#if LVGL_VERSION_MAJOR >= 8
const lv_font_t watch_font_danish_12 = {
#else
lv_font_t watch_font_danish_12 = {
#endif
    .get_glyph_dsc = lv_font_get_glyph_dsc_fmt_txt,    /*Function pointer to get glyph's data*/
    .get_glyph_bitmap = lv_font_get_bitmap_fmt_txt,    /*Function pointer to get glyph's bitmap*/
    .line_height = 15,          /*The maximum line height required by the font*/
    .base_line = 3,             /*Baseline measured from the bottom of the line*/
#if !(LVGL_VERSION_MAJOR == 6 && LVGL_VERSION_MINOR == 0)
    .subpx = LV_FONT_SUBPX_NONE,
#endif
#if LV_VERSION_CHECK(7, 4, 0) || LVGL_VERSION_MAJOR >= 8
    .underline_position = -1,
    .underline_thickness = 1,
#endif
    .dsc = &font_dsc,          /*The custom font data. Will be accessed by `get_glyph_bitmap/dsc` */
#if LV_VERSION_CHECK(8, 2, 0) || LVGL_VERSION_MAJOR >= 9
    .fallback = &lv_font_montserrat_12,
#endif
    .user_data = NULL,
};



#endif /*#if WATCH_FONT_DANISH_12*/

