/*******************************************************************************
 * Size: 8 px
 * Bpp: 4
 * Opts: --font lvgl/scripts/built_in_font/Montserrat-Medium.ttf -r 0xC5,0xC6,0xD8,0xE5,0xE6,0xF8 --size 8 --bpp 4
 *       --no-compress --no-prefilter --format lvgl --lv-font-name watch_font_danish_8 --lv-fallback lv_font_montserrat_8
 *       (lv_font_conv 1.5.3)
 *
 * Danish letters (ÆØÅæøå) only; all other glyphs come from the fallback lv_font_montserrat_8.
 * line_height/base_line are copied from lv_font_montserrat_8 so mixed text shares one baseline.
 ******************************************************************************/

#include "lvgl.h"

#ifndef WATCH_FONT_DANISH_8
#define WATCH_FONT_DANISH_8 1
#endif

#if WATCH_FONT_DANISH_8

/*-----------------
 *    BITMAPS
 *----------------*/

/*Store the image of the glyphs*/
static LV_ATTRIBUTE_LARGE_CONST const uint8_t glyph_bitmap[] = {
    /* U+00C5 "Å" */
    0x0, 0x4, 0x40, 0x0, 0x0, 0x56, 0x0, 0x0,
    0x4, 0x30, 0x0, 0x0, 0xb8, 0x0, 0x0, 0x38,
    0xa1, 0x0, 0xb, 0x13, 0x90, 0x4, 0xd9, 0x9d,
    0x10, 0xb1, 0x0, 0x39,

    /* U+00C6 "Æ" */
    0x0, 0x1, 0xde, 0xaa, 0x80, 0x0, 0xa4, 0xa0,
    0x0, 0x0, 0x57, 0x2d, 0xaa, 0x40, 0x1d, 0x9a,
    0xa0, 0x0, 0xa, 0x20, 0x2e, 0xaa, 0x90,

    /* U+00D8 "Ø" */
    0x0, 0x0, 0x9, 0x0, 0x7b, 0xbf, 0x50, 0x59,
    0x6, 0x5c, 0x19, 0x32, 0x70, 0x84, 0x5a, 0x90,
    0x1c, 0x10, 0xfd, 0xbb, 0x30, 0x13, 0x0, 0x0,
    0x0,

    /* U+00E5 "å" */
    0x2, 0x50, 0x0, 0x25, 0x0, 0x29, 0x98, 0x2,
    0x98, 0xd1, 0x84, 0xc, 0x13, 0xb9, 0xd1,

    /* U+00E6 "æ" */
    0x29, 0x99, 0x99, 0xa1, 0x29, 0x8d, 0x98, 0x96,
    0x84, 0xc, 0x50, 0x10, 0x3b, 0xa6, 0xaa, 0xb1,

    /* U+00F8 "ø" */
    0x0, 0x0, 0x21, 0xaa, 0xf2, 0x84, 0x55, 0xa8,
    0x65, 0x3a, 0x1f, 0xaa, 0x12, 0x10, 0x0
};


/*---------------------
 *  GLYPH DESCRIPTION
 *--------------------*/

static const lv_font_fmt_txt_glyph_dsc_t glyph_dsc[] = {
    {.bitmap_index = 0, .adv_w = 0, .box_w = 0, .box_h = 0, .ofs_x = 0, .ofs_y = 0} /* id = 0 reserved */,
    {.bitmap_index = 0, .adv_w = 94, .box_w = 7, .box_h = 8, .ofs_x = -1, .ofs_y = 0},
    {.bitmap_index = 28, .adv_w = 134, .box_w = 9, .box_h = 5, .ofs_x = -1, .ofs_y = 0},
    {.bitmap_index = 51, .adv_w = 108, .box_w = 7, .box_h = 7, .ofs_x = 0, .ofs_y = -1},
    {.bitmap_index = 76, .adv_w = 77, .box_w = 5, .box_h = 6, .ofs_x = 0, .ofs_y = 0},
    {.bitmap_index = 91, .adv_w = 127, .box_w = 8, .box_h = 4, .ofs_x = 0, .ofs_y = 0},
    {.bitmap_index = 107, .adv_w = 81, .box_w = 5, .box_h = 6, .ofs_x = 0, .ofs_y = -1}
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
    2, -1, 0, -1, 0, 0, -1, -1,
    -1, 0, 0, 0, 0, 0, 0, 0,
    0, 0, -2, 0, -1, 0, -1, 0
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

extern const lv_font_t lv_font_montserrat_8;


/*-----------------
 *  PUBLIC FONT
 *----------------*/

/*Initialize a public general font descriptor*/
#if LVGL_VERSION_MAJOR >= 8
const lv_font_t watch_font_danish_8 = {
#else
lv_font_t watch_font_danish_8 = {
#endif
    .get_glyph_dsc = lv_font_get_glyph_dsc_fmt_txt,    /*Function pointer to get glyph's data*/
    .get_glyph_bitmap = lv_font_get_bitmap_fmt_txt,    /*Function pointer to get glyph's bitmap*/
    .line_height = 10,          /*The maximum line height required by the font*/
    .base_line = 2,             /*Baseline measured from the bottom of the line*/
#if !(LVGL_VERSION_MAJOR == 6 && LVGL_VERSION_MINOR == 0)
    .subpx = LV_FONT_SUBPX_NONE,
#endif
#if LV_VERSION_CHECK(7, 4, 0) || LVGL_VERSION_MAJOR >= 8
    .underline_position = -1,
    .underline_thickness = 0,
#endif
    .dsc = &font_dsc,          /*The custom font data. Will be accessed by `get_glyph_bitmap/dsc` */
#if LV_VERSION_CHECK(8, 2, 0) || LVGL_VERSION_MAJOR >= 9
    .fallback = &lv_font_montserrat_8,
#endif
    .user_data = NULL,
};



#endif /*#if WATCH_FONT_DANISH_8*/

