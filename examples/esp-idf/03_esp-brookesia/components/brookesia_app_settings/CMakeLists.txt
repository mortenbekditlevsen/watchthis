idf_component_register(
    SRCS "esp_brookesia_app_settings.cpp" "assets/esp_brookesia_app_icon_launcher_settings_112_112.c"
    INCLUDE_DIRS "." "include"
    REQUIRES lvgl__lvgl nvs_flash esp32_c6_touch_amoled_2_06
    # The app registers itself through a static constructor, so keep it even though nothing references it
    WHOLE_ARCHIVE
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wno-missing-field-initializers)
