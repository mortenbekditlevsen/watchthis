# Customizable watch faces (Embedded Swift on LVGL). The face format, layout and geometry are the shared Swift
# package WatchFaceKit (also used by the iOS app), compiled here from its sources; this component renders faces and
# lets the user swipe between them. C API in include/watch_faces.h; format in docs/watch-face-format.md.
idf_component_register(
    SRCS /dev/null # Swift sources are added below
    INCLUDE_DIRS "include"
    REQUIRES swift_support lvgl__lvgl file_store step_counter watch_fonts freertos esp_rom heap
)

include(${CMAKE_CURRENT_LIST_DIR}/../swift_support/swift_component.cmake)
swift_component_setup(${CMAKE_CURRENT_LIST_DIR}/BridgingHeader.h)

set(KIT ${CMAKE_CURRENT_LIST_DIR}/WatchFaceKit/Sources/WatchFaceKit)
target_sources(${COMPONENT_LIB}
    PRIVATE
    ${KIT}/Model.swift
    ${KIT}/TLV.swift
    ${KIT}/Coding.swift
    ${KIT}/Geometry.swift
    ${KIT}/Background.swift
    ${KIT}/Text.swift
    ${KIT}/Builtins.swift
    ${KIT}/PNG.swift
    ${KIT}/Fireworks.swift
    ${KIT}/Weather.swift
    LV.swift
    FaceRenderer.swift
    ImageWorker.swift
    FaceStore.swift
    Carousel.swift
    Birthday.swift
    WeatherApp.swift
)
