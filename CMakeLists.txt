cmake_minimum_required(VERSION 4.0)
project(clerk LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 26)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 26)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

include(FetchContent)
set(SPDLOG_USE_STD_FORMAT ON CACHE BOOL "" FORCE)
FetchContent_Declare(spdlog GIT_REPOSITORY https://github.com/gabime/spdlog.git GIT_TAG v1.17.0 GIT_SHALLOW ON)
FetchContent_MakeAvailable(spdlog)

add_library(clerk_core STATIC src/core/features.cpp src/core/match.cpp)
target_include_directories(clerk_core PUBLIC src)
target_link_libraries(clerk_core PUBLIC spdlog::spdlog)
target_compile_options(clerk_core PRIVATE -Wall -Wextra)

# Apple's libraries
add_library(clerk_platform STATIC src/platform/analyze.mm)
target_link_libraries(clerk_platform PUBLIC clerk_core
        "-framework Foundation" "-framework CoreGraphics" "-framework ImageIO" "-framework Vision"
        "-framework AVFoundation" "-framework CoreMedia" "-framework CoreVideo" "-framework UniformTypeIdentifiers")
target_compile_options(clerk_platform PRIVATE -fobjc-arc -Wall -Wextra)

add_executable(calibrate tools/calibrate.cpp)
target_link_libraries(calibrate PRIVATE clerk_platform)

add_executable(clerk main.cpp)
