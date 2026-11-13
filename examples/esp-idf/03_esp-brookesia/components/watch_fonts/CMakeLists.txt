idf_component_register(
    # Montserrat with the Danish letters, in each size LVGL builds Montserrat in (see include/watch_fonts.h)
    SRCS "watch_font_danish_8.c" "watch_font_danish_10.c" "watch_font_danish_12.c" "watch_font_danish_14.c" "watch_font_danish_16.c" "watch_font_danish_18.c" "watch_font_danish_20.c" "watch_font_danish_22.c" "watch_font_danish_24.c" "watch_font_danish_26.c" "watch_font_danish_28.c" "watch_font_danish_30.c" "watch_font_danish_32.c" "watch_font_danish_34.c" "watch_font_danish_36.c" "watch_font_danish_38.c" "watch_font_danish_40.c" "watch_font_danish_42.c" "watch_font_danish_44.c"
         "watch_font_number_66.c"
         "watch_font_read_20.c" "watch_font_read_24.c" "watch_font_read_28.c"
    INCLUDE_DIRS "include"
    REQUIRES lvgl__lvgl
)
