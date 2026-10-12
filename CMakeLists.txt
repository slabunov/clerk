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
add_library(clerk_platform STATIC src/platform/analyze.mm src/platform/files.mm)
target_link_libraries(clerk_platform PUBLIC clerk_core
        "-framework Foundation" "-framework CoreGraphics" "-framework ImageIO" "-framework Vision"
        "-framework AVFoundation" "-framework CoreMedia" "-framework CoreVideo" "-framework UniformTypeIdentifiers"
        "-framework AppKit")
target_compile_options(clerk_platform PRIVATE -fobjc-arc -Wall -Wextra)

add_executable(calibrate tools/calibrate.cpp)
target_link_libraries(calibrate PRIVATE clerk_platform)

list(APPEND CMAKE_PREFIX_PATH /opt/homebrew)
find_package(Qt6 6.8 REQUIRED COMPONENTS Quick QuickControls2)
qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(clerk MACOSX_BUNDLE src/app/main.cpp src/app/session.cpp src/app/session.hpp)
set_target_properties(clerk PROPERTIES MACOSX_BUNDLE_BUNDLE_NAME Clerk) # name in the menu bar; keep the file name = target name, CLion runs by target name
qt_add_qml_module(clerk URI Clerk QML_FILES
        src/app/qml/Main.qml src/app/qml/ScanView.qml src/app/qml/ResultsView.qml src/app/qml/Inspector.qml)
target_include_directories(clerk PRIVATE src/app)
target_link_libraries(clerk PRIVATE clerk_platform Qt6::Quick Qt6::QuickControls2)
target_compile_options(clerk PRIVATE -Wall -Wextra)
