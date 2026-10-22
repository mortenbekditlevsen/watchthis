idf_component_register(
    SRCS "esp_brookesia_app_stopwatch.cpp" "assets/esp_brookesia_app_icon_launcher_stopwatch_112_112.c"
    INCLUDE_DIRS "."
    REQUIRES watch_tools lvgl__lvgl
    # The app registers itself through a static constructor, so keep it even though nothing references it
    WHOLE_ARCHIVE
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wno-missing-field-initializers)
