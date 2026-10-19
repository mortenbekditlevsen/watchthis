idf_component_register(
    SRCS "esp_brookesia_app_cats.cpp" "cats_jpeg_decoder.cpp" "assets/esp_brookesia_app_icon_launcher_cats_112_112.c"
    INCLUDE_DIRS "."
    REQUIRES file_store lvgl__lvgl
    # The app registers itself through a static constructor, so keep it even though nothing references it
    WHOLE_ARCHIVE
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wno-missing-field-initializers)

# Preload the built-in cat photos into the `store` partition (see components/file_store); users can delete them
file(GLOB cat_images CONFIGURE_DEPENDS "${CMAKE_CURRENT_LIST_DIR}/images/*.jpg")
set(preload_photos "${CMAKE_BINARY_DIR}/store_preload/photos")
file(REMOVE_RECURSE "${preload_photos}")
file(MAKE_DIRECTORY "${preload_photos}")
file(COPY ${cat_images} DESTINATION "${preload_photos}")
