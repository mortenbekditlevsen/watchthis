/*******************************************************************************
 * Size: 10 px
 * Bpp: 4
 * Opts: --font lvgl/scripts/built_in_font/Montserrat-Medium.ttf -r 0xC5,0xC6,0xD8,0xE5,0xE6,0xF8 --size 10 --bpp 4
 *       --no-compress --no-prefilter --format lvgl --lv-font-name watch_font_danish_10 --lv-fallback lv_font_montserrat_10
 *       (lv_font_conv 1.5.3)
 *
 * Danish letters (ÆØÅæøå) only; all other glyphs come from the fallback lv_font_montserrat_10.
 * line_height/base_line are copied from lv_font_montserrat_10 so mixed text shares one baseline.
 ******************************************************************************/

#include "lvgl.h"

#ifndef WATCH_FONT_DANISH_10
#define WATCH_FONT_DANISH_10 1
#endif

#if WATCH_FONT_DANISH_10

/*-----------------
 *    BITMAPS
 *----------------*/

/*Store the image of the glyphs*/
static LV_ATTRIBUTE_LARGE_CONST const uint8_t glyph_bitmap[] = {
    /* U+00C5 "Å" */
    0x0, 0x2, 0x64, 0x0, 0x0, 0x0, 0x25, 0x40,
    0x0, 0x0, 0x1, 0xf6, 0x0, 0x0, 0x0, 0x88,
    0xc0, 0x0, 0x0, 0xd, 0x9, 0x40, 0x0, 0x6,
    0x70, 0x2b, 0x0, 0x0, 0xdc, 0xcc, 0xe3, 0x0,
    0x59, 0x0, 0x4, 0xa0, 0xc, 0x30, 0x0, 0xd,
    0x10,

    /* U+00C6 "Æ" */
    0x0, 0x0, 0x2e, 0xfd, 0xdd, 0x90, 0x0, 0xb,
    0x5d, 0x0, 0x0, 0x0, 0x5, 0x82, 0xd0, 0x0,
    0x0, 0x0, 0xc0, 0x2f, 0xcc, 0xc4, 0x0, 0x8d,
    0xcc, 0xd0, 0x0, 0x0, 0x2b, 0x0, 0x2d, 0x0,
    0x0, 0xb, 0x40, 0x2, 0xfd, 0xdd, 0xb0,

    /* U+00D8 "Ø" */
    0x0, 0x0, 0x0, 0x23, 0x1, 0x9d, 0xdd, 0xf0,
    0xd, 0x60, 0xc, 0xf4, 0x5b, 0x0, 0x65, 0x4b,
    0x78, 0x3, 0x90, 0x1e, 0x5b, 0x1a, 0x0, 0x4b,
    0xd, 0xf2, 0x2, 0xd4, 0x8, 0xfd, 0xdc, 0x40,
    0x5, 0x0, 0x0, 0x0,

    /* U+00E5 "å" */
    0x0, 0x65, 0x0, 0x2, 0x57, 0x0, 0x0, 0x65,
    0x0, 0x1b, 0xcd, 0x60, 0x1, 0x0, 0xe0, 0x1a,
    0xaa, 0xf1, 0x78, 0x0, 0xe1, 0x2c, 0xaa, 0xe1,

    /* U+00E6 "æ" */
    0x1b, 0xcc, 0x69, 0xcc, 0x60, 0x1, 0x0, 0xf7,
    0x0, 0xc3, 0x19, 0xaa, 0xfa, 0xaa, 0xb5, 0x78,
    0x1, 0xe7, 0x0, 0x20, 0x2c, 0xdc, 0x49, 0xcc,
    0x90,

    /* U+00F8 "ø" */
    0x0, 0x0, 0x3, 0x7, 0xdd, 0xf2, 0x5c, 0x6,
    0xab, 0x87, 0x26, 0x1e, 0x5c, 0x90, 0x7b, 0xf,
    0xfd, 0xb1, 0x13, 0x0, 0x0
};


/*---------------------
 *  GLYPH DESCRIPTION
 *--------------------*/

static const lv_font_fmt_txt_glyph_dsc_t glyph_dsc[] = {
    {.bitmap_index = 0, .adv_w = 0, .box_w = 0, .box_h = 0, .ofs_x = 0, .ofs_y = 0} /* id = 0 reserved */,
    {.bitmap_index = 0, .adv_w = 117, .box_w = 9, .box_h = 9, .ofs_x = -1, .ofs_y = 0},
    {.bitmap_index = 41, .adv_w = 168, .box_w = 11, .box_h = 7, .ofs_x = -1, .ofs_y = 0},
    {.bitmap_index = 80, .adv_w = 134, .box_w = 8, .box_h = 9, .ofs_x = 0, .ofs_y = -1},
    {.bitmap_index = 116, .adv_w = 96, .box_w = 6, .box_h = 8, .ofs_x = 0, .ofs_y = 0},
    {.bitmap_index = 140, .adv_w = 158, .box_w = 10, .box_h = 5, .ofs_x = 0, .ofs_y = 0},
    {.bitmap_index = 165, .adv_w = 102, .box_w = 6, .box_h = 7, .ofs_x = 0, .ofs_y = -1}
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
    2, -2, 0, -1, 0, 0, -1, -1,
    -2, 0, 0, 0, 0, 0, 0, 0,
    0, 0, -2, 0, -2, 0, -1, 0
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

extern const lv_font_t lv_font_montserrat_10;


/*-----------------
 *  PUBLIC FONT
 *----------------*/

/*Initialize a public general font descriptor*/
#if LVGL_VERSION_MAJOR >= 8
const lv_font_t watch_font_danish_10 = {
#else
lv_font_t watch_font_danish_10 = {
#endif
    .get_glyph_dsc = lv_font_get_glyph_dsc_fmt_txt,    /*Function pointer to get glyph's data*/
    .get_glyph_bitmap = lv_font_get_bitmap_fmt_txt,    /*Function pointer to get glyph's bitmap*/
    .line_height = 11,          /*The maximum line height required by the font*/
    .base_line = 2,             /*Baseline measured from the bottom of the line*/
#if !(LVGL_VERSION_MAJOR == 6 && LVGL_VERSION_MINOR == 0)
    .subpx = LV_FONT_SUBPX_NONE,
#endif
#if LV_VERSION_CHECK(7, 4, 0) || LVGL_VERSION_MAJOR >= 8
    .underline_position = -1,
    .underline_thickness = 1,
#endif
    .dsc = &font_dsc,          /*The custom font data. Will be accessed by `get_glyph_bitmap/dsc` */
#if LV_VERSION_CHECK(8, 2, 0) || LVGL_VERSION_MAJOR >= 9
    .fallback = &lv_font_montserrat_10,
#endif
    .user_data = NULL,
};



#endif /*#if WATCH_FONT_DANISH_10*/

