idf_component_register(
    SRCS "esp_brookesia_app_sync.cpp" "assets/esp_brookesia_app_icon_launcher_sync_112_112.c"
    INCLUDE_DIRS "."
    REQUIRES ble_sync file_store music_player lvgl__lvgl watch_fonts
    # The app registers itself through a static constructor, so keep it even though nothing references it
    WHOLE_ARCHIVE
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wno-missing-field-initializers)
