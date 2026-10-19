idf_component_register(
    SRCS "main.cpp" "time_sync.cpp" "rtc_pcf85063.cpp" "pmu.cpp" "power_manager.cpp" "battery_log.cpp" "audio_power.cpp"
         "watch_name.cpp"
    INCLUDE_DIRS ".")

target_compile_options(${COMPONENT_LIB} PUBLIC -Wno-missing-field-initializers)

# Initial watch name / home screen title (main.cpp): HOME_TITLE="Mit ur" idf.py build. Only used on a watch that
# has no name stored yet (watch_name.cpp); after that the stored name wins (changed via BLE, SetName).
# Read when CMake configures, so after changing it run `idf.py reconfigure` (or a clean build).
if(DEFINED ENV{HOME_TITLE})
    message(STATUS "Home screen title: $ENV{HOME_TITLE}")
    target_compile_definitions(${COMPONENT_LIB} PRIVATE "HOME_TITLE_TEXT=\"$ENV{HOME_TITLE}\"")
endif()

# Function to get component library
function(get_component_library component_name output_var)
    # Get the exact component name
    idf_build_get_property(build_components BUILD_COMPONENTS)
    set(TARGET_COMPONENT "")
    foreach(COMPONENT ${build_components})
        if(COMPONENT MATCHES "${component_name}" OR COMPONENT MATCHES "espressif__${component_name}")
            set(TARGET_COMPONENT ${COMPONENT})
            break()
        endif()
    endforeach()

    # Get the component library
    if(TARGET_COMPONENT STREQUAL "")
        message(FATAL_ERROR "Component '${component_name}' not found.")
    else()
        idf_component_get_property(COMPONENT_LIB ${TARGET_COMPONENT} COMPONENT_LIB)
        set(${output_var} ${COMPONENT_LIB} PARENT_SCOPE)
    endif()
endfunction()

get_component_library("lvgl" LVGL_LIB)
target_compile_options(
    ${LVGL_LIB}
    PUBLIC
        "-Wno-attributes"
)
# The ESP32-C6 ROM has its own (older, differently laid out) TJPGD, and esp32c6.rom.ld binds jd_prepare/jd_decomp
# to it, overriding LVGL's copies while the rest of LVGL's TJPGD stays in use -> memory corruption when decoding.
# Rename LVGL's two functions so its decoder uses its own code throughout.
target_compile_definitions(
    ${LVGL_LIB}
    PRIVATE
        "jd_prepare=lv_tjpgd_jd_prepare"
        "jd_decomp=lv_tjpgd_jd_decomp"
)
idf_build_get_property(build_components BUILD_COMPONENTS)
if("lvgl__lvgl" IN_LIST build_components)
    idf_component_get_property(LVGL_LIB lvgl__lvgl COMPONENT_LIB)
    if(TARGET ${LVGL_LIB})
        target_compile_options(${LVGL_LIB} PRIVATE -Wno-error=attributes -Wno-error=cpp)
    endif()
endif()
idf_build_get_property(build_components BUILD_COMPONENTS)
if("chmorgan__esp-audio-player" IN_LIST build_components AND "esp_driver_i2s" IN_LIST build_components)
    idf_component_get_property(AUDIO_PLAYER_LIB chmorgan__esp-audio-player COMPONENT_LIB)
    if(TARGET ${AUDIO_PLAYER_LIB})
        target_link_libraries(${AUDIO_PLAYER_LIB} PUBLIC idf::esp_driver_i2s)
    endif()
endif()
