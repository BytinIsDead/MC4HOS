# MC4HOS native core: NAPI bridge, embedded JVM loader, XComponent surface,
# input dispatch and log capture.
#
# Copyright (C) 2026 MC4HOS Contributors
# SPDX-License-Identifier: MPL-2.0
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

# Native window APIs are optional for the core bridge: we only hand the
# XComponent window pointer through to EGL, and the OH_NativeXComponent_*
# symbols live in libace_ndk.z.so. Some HMOS SDK sysroots do not export
# libnativewindow.so, so probe both OHOS naming conventions and link it
# only when present — an unconditional link fails the generate step with
# "variable ... set to NOTFOUND" on those SDKs.
find_library(nativewindow-lib
        NAMES nativewindow nativewindow.z)

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
        message(STATUS "MC4HOS: libnativewindow not in this SDK sysroot - skipped (no OH_NativeWindow symbols used)")
endif()
