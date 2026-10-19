# BLE link to the paired phone (Embedded Swift on NimBLE): pairing, time sync, later file upload. C API in
# include/ble_sync.h; protocol in docs/watch-ble-protocol.md. Swift helpers adapted from qrbuddy.
idf_component_register(
    SRCS /dev/null # Swift sources are added below
    INCLUDE_DIRS "include"
    REQUIRES swift_support bt pairing file_store
)

idf_build_get_property(target IDF_TARGET)
idf_build_get_property(arch IDF_TARGET_ARCH)

if("${arch}" STREQUAL "xtensa")
    message(FATAL_ERROR "Not supported target: ${target}")
endif()

if(${target} STREQUAL "esp32c2" OR ${target} STREQUAL "esp32c3")
    set(march_flag "rv32imc_zicsr_zifencei")
    set(mabi_flag "ilp32")
elseif(${target} STREQUAL "esp32p4")
    set(march_flag "rv32imafc_zicsr_zifencei")
    set(mabi_flag "ilp32f")
else()
    set(march_flag "rv32imac_zicsr_zifencei")
    set(mabi_flag "ilp32")
endif()

# Clear the default COMPILE_OPTIONS which include a lot of C/C++ specific compiler flags that the Swift compiler will not accept
set_target_properties(${COMPONENT_LIB} PROPERTIES COMPILE_OPTIONS "")

# Compute -Xcc flags to set up the C and C++ header search paths for Swift (for bridging header).
set(SWIFT_INCLUDES)
foreach(dir ${CMAKE_C_IMPLICIT_INCLUDE_DIRECTORIES})
    string(CONCAT SWIFT_INCLUDES ${SWIFT_INCLUDES} "-Xcc ")
    string(CONCAT SWIFT_INCLUDES ${SWIFT_INCLUDES} "-I${dir} ")
endforeach()
foreach(dir ${CMAKE_CXX_IMPLICIT_INCLUDE_DIRECTORIES})
    string(CONCAT SWIFT_INCLUDES ${SWIFT_INCLUDES} "-Xcc ")
    string(CONCAT SWIFT_INCLUDES ${SWIFT_INCLUDES} "-I${dir} ")
endforeach()

# Swift compiler flags to build in Embedded Swift mode, optimize for size, choose the right ISA, ABI, etc.
target_compile_options(${COMPONENT_LIB} PUBLIC "$<$<COMPILE_LANGUAGE:Swift>:SHELL:
    -target riscv32-none-none-eabi
    -Xfrontend -function-sections -enable-experimental-feature Embedded -wmo -parse-as-library -Osize
    -Xcc -march=${march_flag} -Xcc -mabi=${mabi_flag}

    -pch-output-dir /tmp
    -Xfrontend -enable-single-module-llvm-emission

    ${SWIFT_INCLUDES}

    -import-bridging-header ${CMAKE_CURRENT_LIST_DIR}/BridgingHeader.h
    >")

# Pick the Swift compiler explicitly. The Xcode-bundled toolchain (/usr/bin/swiftc) has no
# RISC-V LLVM target and crashes while generating the bridging-header PCH, so prefer the
# swiftly shim (which honours the .swift-version file), then any other swiftc on PATH.
if(NOT CMAKE_Swift_COMPILER)
    find_program(SWIFTLY_SWIFTC swiftc
        PATHS "$ENV{SWIFTLY_BIN_DIR}" "$ENV{HOME}/.swiftly/bin"
        NO_DEFAULT_PATH)
    if(SWIFTLY_SWIFTC)
        set(CMAKE_Swift_COMPILER "${SWIFTLY_SWIFTC}")
    else()
        find_program(CMAKE_Swift_COMPILER swiftc)
    endif()
    message(STATUS "Swift compiler: ${CMAKE_Swift_COMPILER}")
endif()

# Enable Swift support in CMake, force Whole Module builds (required by Embedded Swift), and use "CMAKE_Swift_COMPILER_WORKS" to
# skip the trial compilations which don't (yet) correctly work when cross-compiling.
set(CMAKE_Swift_COMPILER_WORKS YES)
set(CMAKE_Swift_COMPILATION_MODE_DEFAULT wholemodule)
set(CMAKE_Swift_COMPILATION_MODE wholemodule)
enable_language(Swift)

target_sources(${COMPONENT_LIB}
    PRIVATE
    BleSync.swift
    GATTServer.swift
    Pairing.swift
    BluetoothAddress.swift
    ByteSwap.swift
    CompanyIdentifier.swift
    Data.swift
    Encoder.swift
    Error.swift
    GAPData.swift
    GAPDataType.swift
    GAPFlags.swift
    GAPManufacturerSpecificData.swift
    GAPServiceUUIDs.swift
    GAPShortLocalName.swift
    Hexadecimal.swift
    Integer.swift
    LowEnergyAddressType.swift
    LowEnergyAdvertisingData.swift
    NimbleUUID.swift
    String.swift
    UInt128.swift
    UUID.swift
)
