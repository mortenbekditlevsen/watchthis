# The Stopur and Timer apps' logic and UI in Embedded Swift (on LVGL). The logic is the Swift package WatchToolsKit
# (tested on a computer), compiled here from its sources; brookesia_app_stopwatch / brookesia_app_timer are the thin
# C++ app shells. C API in include/watch_tools.h.
idf_component_register(
    SRCS /dev/null # Swift sources are added below
    INCLUDE_DIRS "include"
    REQUIRES swift_support lvgl__lvgl watch_fonts music_player freertos esp_timer
)

include(${CMAKE_CURRENT_LIST_DIR}/../swift_support/swift_component.cmake)
swift_component_setup(${CMAKE_CURRENT_LIST_DIR}/BridgingHeader.h)

set(KIT ${CMAKE_CURRENT_LIST_DIR}/WatchToolsKit/Sources/WatchToolsKit)
target_sources(${COMPONENT_LIB}
    PRIVATE
    ${KIT}/Stopwatch.swift
    ${KIT}/Countdown.swift
    UI.swift
    StopwatchApp.swift
    TimerApp.swift
)
