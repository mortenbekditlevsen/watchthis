idf_component_register(
    SRCS "esp_brookesia_app_particles.cpp" "assets/esp_brookesia_app_icon_launcher_particles_112_112.c"
    INCLUDE_DIRS "."
    REQUIRES particle_effects
    # The app registers itself through a static constructor, so keep it even though nothing references it
    WHOLE_ARCHIVE
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wno-missing-field-initializers)
