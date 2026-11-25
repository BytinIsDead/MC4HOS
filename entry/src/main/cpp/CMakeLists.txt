# MC4HOS native core: NAPI bridge, embedded JVM loader, XComponent surface,
# input dispatch and log capture.
#
# Copyright (C) 2026 MC4HOS Contributors
# SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

cmake_minimum_required(VERSION 3.5.0)
project(mc4hos_core)

# Built for BOTH OHOS 64-bit ABIs from the same sources: arm64-v8a
# (phones/tablets) and x86_64 (Intel 2-in-1s, OHOS emulator). hvigor
# invokes this file once per ABI with OHOS_ARCH set; no
# architecture-specific flags or sources are required. The OHOS NDK
# provides no 32-bit x86 ABI, and the embedded JVM requires 64-bit anyway.

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
add_compile_options(-fexceptions -frtti -O2)

# ASCII-only status line: em-dashes render as mojibake in Windows consoles.
message(STATUS "MC4HOS native core - target ABI: ${OHOS_ARCH}")

include_directories(${CMAKE_CURRENT_SOURCE_DIR}/include)

add_library(mc4hos_core SHARED
        napi_init.cpp
        src/log_capture.cpp
        src/input_bridge.cpp
        src/jni_bridge.cpp
        src/game_surface.cpp
        src/jvm_loader.cpp)

find_library(hilog-lib        hilog_ndk.z)
find_library(napi-lib         ace_napi.z)
find_library(ace-ndk-lib      ace_ndk.z)
find_library(egl-lib          EGL)
find_library(gles-lib         GLESv3)
find_library(dl-lib           dl)
find_library(nativewindow-manager-lib native_window_manager)
find_library(ohinput-lib ohinput)

# The GLFW bridge uses OH_NativeWindow* directly. Probe both OHOS naming
# conventions because SDK sysroots differ in whether the archive carries the
# .z suffix.
find_library(nativewindow-lib
        NAMES native_window nativewindow native_window.z nativewindow.z)

target_link_libraries(mc4hos_core PUBLIC
        ${napi-lib}
        ${ace-ndk-lib}
        ${hilog-lib}
        ${egl-lib}
        ${gles-lib}
        ${dl-lib})

if(nativewindow-lib)
        target_link_libraries(mc4hos_core PUBLIC ${nativewindow-lib})
else()
        message(STATUS "MC4HOS: libnativewindow not in this SDK sysroot")
endif()

if(NOT nativewindow-lib OR NOT nativewindow-manager-lib OR NOT ohinput-lib)
        message(FATAL_ERROR "MC4HOS GLFW bridge requires nativewindow, native_window_manager and ohinput")
endif()

add_library(meowcraftbridge SHARED
        meowcraftbridge/egl_gl.c
        meowcraftbridge/input_bridge.c
        meowcraftbridge/meowcraftbridge_environ.c
        meowcraftbridge/meowpasteboard.c
        meowcraftbridge/meowqos.c
        meowcraftbridge/meowbt.c)
set_target_properties(meowcraftbridge PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON)
target_include_directories(meowcraftbridge PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/meowcraftbridge)
target_link_libraries(meowcraftbridge PUBLIC
        ${hilog-lib}
        ${nativewindow-manager-lib}
        ${nativewindow-lib}
        ${ohinput-lib}
        ${egl-lib}
        ${dl-lib})
