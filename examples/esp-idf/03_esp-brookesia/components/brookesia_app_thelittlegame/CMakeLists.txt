idf_component_register(
    SRCS "esp_brookesia_app_thelittlegame.cpp" "assets/esp_brookesia_app_icon_launcher_thelittlegame_112_112.c"
    INCLUDE_DIRS "."
    REQUIRES thelittlegame esp_driver_gpio esp_timer
    # The app registers itself through a static constructor, so keep it even though nothing references it
    WHOLE_ARCHIVE
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wno-missing-field-initializers)
