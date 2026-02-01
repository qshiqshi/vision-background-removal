cmake_minimum_required(VERSION 3.28)

# Plugin metadata
set(PLUGIN_NAME "vision-background-removal")
set(PLUGIN_VERSION "1.0.0")
set(PLUGIN_AUTHOR "Andreas Kuschner")

project(${PLUGIN_NAME} VERSION ${PLUGIN_VERSION})

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Set Objective-C++ for macOS
set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)

# macOS specific settings
if(APPLE)
    set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "Build for Apple Silicon")
    set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING "Minimum macOS version")

    # Enable ARC (Automatic Reference Counting)
    set(CMAKE_OBJCXX_FLAGS "${CMAKE_OBJCXX_FLAGS} -fobjc-arc")
endif()

# Find OBS
set(OBS_APP_PATH "/Applications/OBS.app")
set(OBS_FRAMEWORKS_PATH "${OBS_APP_PATH}/Contents/Frameworks")

# Use local headers for compilation
set(OBS_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/deps/obs-studio/libobs")

# Find libobs framework from OBS.app
find_library(OBS_LIBRARY
    NAMES libobs
    PATHS "${OBS_FRAMEWORKS_PATH}"
    NO_DEFAULT_PATH
)

if(NOT OBS_LIBRARY)
    # Fallback: link directly to framework
    set(OBS_LIBRARY "${OBS_FRAMEWORKS_PATH}/libobs.framework")
endif()

message(STATUS "OBS Include: ${OBS_INCLUDE_DIR}")
message(STATUS "OBS Library: ${OBS_LIBRARY}")

# Source files
set(PLUGIN_SOURCES
    src/plugin-main.mm
    src/background-removal-filter.mm
    src/vision-processor.mm
)

set(PLUGIN_HEADERS
    src/plugin-main.h
    src/background-removal-filter.h
    src/vision-processor.h
)

# Create the plugin module
add_library(${PLUGIN_NAME} MODULE
    ${PLUGIN_SOURCES}
    ${PLUGIN_HEADERS}
)

# Include directories
target_include_directories(${PLUGIN_NAME} PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${OBS_INCLUDE_DIR}
    ${OBS_INCLUDE_DIR}/util
    ${OBS_INCLUDE_DIR}/graphics
)

# macOS frameworks
if(APPLE)
    find_library(COCOA_FRAMEWORK Cocoa REQUIRED)
    find_library(COREVIDEO_FRAMEWORK CoreVideo REQUIRED)
    find_library(COREMEDIA_FRAMEWORK CoreMedia REQUIRED)
    find_library(COREIMAGE_FRAMEWORK CoreImage REQUIRED)
    find_library(VISION_FRAMEWORK Vision REQUIRED)
    find_library(METAL_FRAMEWORK Metal REQUIRED)
    find_library(METALPERFORMANCESHADERS_FRAMEWORK MetalPerformanceShaders REQUIRED)
    find_library(ACCELERATE_FRAMEWORK Accelerate REQUIRED)
    find_library(VIDEOTOOLBOX_FRAMEWORK VideoToolbox REQUIRED)

    target_link_libraries(${PLUGIN_NAME} PRIVATE
        ${COCOA_FRAMEWORK}
        ${COREVIDEO_FRAMEWORK}
        ${COREMEDIA_FRAMEWORK}
        ${COREIMAGE_FRAMEWORK}
        ${VISION_FRAMEWORK}
        ${METAL_FRAMEWORK}
        ${METALPERFORMANCESHADERS_FRAMEWORK}
        ${ACCELERATE_FRAMEWORK}
        ${VIDEOTOOLBOX_FRAMEWORK}
    )

    # Set bundle properties
    set_target_properties(${PLUGIN_NAME} PROPERTIES
        BUNDLE TRUE
        BUNDLE_EXTENSION "plugin"
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/cmake/Info.plist.in"
        PREFIX ""
        SUFFIX ".so"
    )
endif()

# Link OBS
target_link_libraries(${PLUGIN_NAME} PRIVATE ${OBS_LIBRARY})

# Compiler options
target_compile_options(${PLUGIN_NAME} PRIVATE
    -Wall
    -Wextra
    -Wno-unused-parameter
    -Wno-gnu-anonymous-struct
    -Wno-nested-anon-types
)

# Install rules
if(APPLE)
    set(OBS_PLUGIN_DIR "$ENV{HOME}/Library/Application Support/obs-studio/plugins/${PLUGIN_NAME}/bin")
    set(OBS_DATA_DIR "$ENV{HOME}/Library/Application Support/obs-studio/plugins/${PLUGIN_NAME}/data")
else()
    set(OBS_PLUGIN_DIR "${CMAKE_INSTALL_PREFIX}/lib/obs-plugins")
    set(OBS_DATA_DIR "${CMAKE_INSTALL_PREFIX}/share/obs/obs-plugins/${PLUGIN_NAME}")
endif()

install(TARGETS ${PLUGIN_NAME}
    LIBRARY DESTINATION "${OBS_PLUGIN_DIR}"
    BUNDLE DESTINATION "${OBS_PLUGIN_DIR}"
)

install(DIRECTORY data/
    DESTINATION "${OBS_DATA_DIR}"
)

# CPack configuration
set(CPACK_PACKAGE_NAME ${PLUGIN_NAME})
set(CPACK_PACKAGE_VERSION ${PLUGIN_VERSION})
set(CPACK_PACKAGE_VENDOR ${PLUGIN_AUTHOR})
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Background removal filter for OBS using Apple Vision Framework")

if(APPLE)
    set(CPACK_GENERATOR "DragNDrop")
endif()

include(CPack)

message(STATUS "")
message(STATUS "========================================")
message(STATUS "OBS Background Removal Plugin for macOS")
message(STATUS "========================================")
message(STATUS "Version: ${PLUGIN_VERSION}")
message(STATUS "Target: Apple Silicon (arm64)")
message(STATUS "Minimum macOS: ${CMAKE_OSX_DEPLOYMENT_TARGET}")
message(STATUS "")
