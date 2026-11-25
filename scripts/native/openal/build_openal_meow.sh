#!/bin/sh
# Copyright (c) 2026 Harmomeow Craft Launcher contributors
# SPDX-License-Identifier: MIT
# MC4HOS adaptations Copyright (C) 2026 MC4HOS Contributors
# SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
#
# Original terms: scripts/licenses/Harmomeow-LICENSE.txt
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Build MC4HOS's HarmonyOS x86_64 port of OpenAL Soft (libopenal.so).
#
# Standalone: every path is passed in, nothing is derived from the caller's
# layout. The source tree is patched in place, so pass a throwaway extraction.
# This scratch adaptation defaults to x86_64 and selects the matching OHOS
# sysroot library instead of the reference script's hardcoded aarch64 library.
#
# Usage:
#   sh build_openal_meow.sh --src DIR --sdk-native DIR --out DIR \
#       [--build DIR] [--patcher FILE] [--api N] [--arch NAME] [--ninja FILE]
#
# Required:
#   --src DIR         openal-soft source tree, checked out at the target tag
#   --sdk-native DIR  OHOS SDK native dir (has build/cmake/ohos.toolchain.cmake,
#                     llvm/, sysroot/ with SLES/OpenSLES_OpenHarmony.h)
#   --out DIR         output dir; receives libopenal.so
#
# Optional:
#   --build DIR       out-of-tree build dir (default: <src>/../build-meow)
#   --patcher FILE    OpenSL patch script (default: patch_openal_ohos.py next to this script)
#   --ohaudio-patcher FILE  OHAudio backend installer (default: patch_openal_ohaudio.py)
#   --events-patcher FILE   SOFT_system_events export fixer (default: patch_openal_events_export.py)
#   --api N           OHOS platform level (default: 23)
#   --arch NAME       OHOS arch: x86_64/arm64-v8a (default: x86_64)
#   --ninja FILE      Ninja executable (default: ninja on PATH)
#   -h, --help        show this help
#
# Requires: cmake, ninja. Emits an OHAudio + OpenSL, musl/libc++_shared build.
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
}

SRC=""
SDK_NATIVE=""
OUT=""
BUILD=""
PATCHER="$HERE/patch_openal_ohos.py"
OHAUDIO_PATCHER="$HERE/patch_openal_ohaudio.py"
EVENTS_PATCHER="$HERE/patch_openal_events_export.py"
API=23
ARCH=x86_64
NINJA=ninja

while [ "$#" -gt 0 ]; do
  case "$1" in
    --src)        SRC="$2"; shift 2 ;;
    --sdk-native) SDK_NATIVE="$2"; shift 2 ;;
    --out)        OUT="$2"; shift 2 ;;
    --build)      BUILD="$2"; shift 2 ;;
    --patcher)    PATCHER="$2"; shift 2 ;;
    --ohaudio-patcher) OHAUDIO_PATCHER="$2"; shift 2 ;;
    --events-patcher) EVENTS_PATCHER="$2"; shift 2 ;;
    --api)        API="$2"; shift 2 ;;
    --arch)       ARCH="$2"; shift 2 ;;
    --ninja)      NINJA="$2"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$SRC" ]        || { echo "error: --src is required" >&2; usage >&2; exit 2; }
[ -n "$SDK_NATIVE" ] || { echo "error: --sdk-native is required" >&2; usage >&2; exit 2; }
[ -n "$OUT" ]        || { echo "error: --out is required" >&2; usage >&2; exit 2; }

OPENSL_CPP="$SRC/alc/backends/opensl.cpp"
TOOLCHAIN="$SDK_NATIVE/build/cmake/ohos.toolchain.cmake"
SYSROOT="$SDK_NATIVE/sysroot"
case "$ARCH" in
  x86_64) OHOS_LIBARCH=x86_64-linux-ohos ;;
  arm64-v8a) OHOS_LIBARCH=aarch64-linux-ohos ;;
  *) echo "error: unsupported --arch: $ARCH (use x86_64/arm64-v8a)" >&2; exit 2 ;;
esac
OPENSL_LIB="$SYSROOT/usr/lib/$OHOS_LIBARCH/libOpenSLES.so"
STRIP="$SDK_NATIVE/llvm/bin/llvm-strip"
READELF="$SDK_NATIVE/llvm/bin/llvm-readelf"
for tool in STRIP READELF; do
  eval "path=\$$tool"
  [ -f "$path" ] || eval "$tool=\"\$path.exe\""
done

[ -f "$OPENSL_CPP" ] || { echo "error: not an openal-soft tree: $SRC" >&2; exit 2; }
[ -f "$TOOLCHAIN" ]  || { echo "error: OHOS toolchain not found: $TOOLCHAIN" >&2; exit 2; }
[ -f "$OPENSL_LIB" ] || { echo "error: libOpenSLES.so not found: $OPENSL_LIB" >&2; exit 2; }
[ -f "$PATCHER" ]    || { echo "error: patcher not found: $PATCHER" >&2; exit 2; }
[ -f "$OHAUDIO_PATCHER" ] || { echo "error: OHAudio patcher not found: $OHAUDIO_PATCHER" >&2; exit 2; }
[ -f "$EVENTS_PATCHER" ] || { echo "error: events patcher not found: $EVENTS_PATCHER" >&2; exit 2; }
[ -f "$STRIP" ] || { echo "error: SDK llvm-strip not found: $STRIP" >&2; exit 2; }
[ -f "$READELF" ] || { echo "error: SDK llvm-readelf not found: $READELF" >&2; exit 2; }
if [ ! -f "$NINJA" ] && ! command -v "$NINJA" >/dev/null 2>&1; then
  echo "error: Ninja not found: $NINJA (use --ninja FILE)" >&2
  exit 2
fi

[ -n "$BUILD" ] || BUILD="$(dirname "$SRC")/build-meow"
mkdir -p "$OUT"
rm -rf "$BUILD"

echo "=== patch OpenSL backend for OHOS ==="
python3 "$PATCHER" "$OPENSL_CPP"

echo "=== install OHAudio backend ==="
python3 "$OHAUDIO_PATCHER" "$SRC"

echo "=== export ALC_SOFT_system_events entry points ==="
python3 "$EVENTS_PATCHER" "$SRC"

echo "=== configure ($ARCH, api $API) ==="
# Force the export-visibility attribute: CMake's cross-compile link test for
# __attribute__((visibility("default"))) fails spuriously on the OHOS toolchain,
# which would otherwise leave ALC_API/AL_API empty and export no symbols.
cmake -G Ninja -S "$SRC" -B "$BUILD" \
  -DCMAKE_MAKE_PROGRAM="$NINJA" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DOHOS_ARCH="$ARCH" -DOHOS_STL=c++_shared -DOHOS_PLATFORM_LEVEL="$API" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DALSOFT_UPDATE_BUILD_VERSION=OFF \
  -DHAVE_GCC_PROTECTED_VISIBILITY=0 -DHAVE_GCC_DEFAULT_VISIBILITY=1 \
  -DOPENSL_INCLUDE_DIR="$SYSROOT/usr/include" \
  -DOPENSL_ANDROID_INCLUDE_DIR="$SYSROOT/usr/include" \
  -DOPENSL_LIBRARY="$OPENSL_LIB" \
  -DALSOFT_BACKEND_OPENSL=ON -DALSOFT_REQUIRE_OPENSL=ON \
  -DALSOFT_BACKEND_OHAUDIO=ON -DALSOFT_REQUIRE_OHAUDIO=ON \
  -DALSOFT_BACKEND_PULSEAUDIO=OFF -DALSOFT_BACKEND_ALSA=OFF -DALSOFT_BACKEND_OSS=OFF \
  -DALSOFT_BACKEND_JACK=OFF -DALSOFT_BACKEND_SNDIO=OFF -DALSOFT_BACKEND_PORTAUDIO=OFF \
  -DALSOFT_BACKEND_SDL2=OFF -DALSOFT_BACKEND_SDL3=OFF -DALSOFT_BACKEND_OBOE=OFF \
  -DALSOFT_BACKEND_PIPEWIRE=OFF \
  -DALSOFT_UTILS=OFF -DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF

echo "=== build ==="
"$NINJA" -C "$BUILD"

set -- "$BUILD"/libopenal.so.*
SO="$1"
[ -f "$SO" ] || { echo "error: libopenal.so not produced" >&2; exit 1; }

"$STRIP" --strip-unneeded "$SO"
cp "$SO" "$OUT/libopenal.so"

# Verify the requested ABI, core ALC exports, and HarmonyOS audio dependencies
# with the SDK's own LLVM tools. The visibility overrides above are essential:
# without them the cross-compile probe can leave every ALC_API/AL_API hidden.
HEADER="$("$READELF" -h "$OUT/libopenal.so")"
case "$ARCH" in
  x86_64)
    printf '%s\n' "$HEADER" | grep -qE 'Machine:[[:space:]]+Advanced Micro Devices X86-64' \
      || { echo "error: libopenal.so is not ELF x86_64" >&2; exit 1; } ;;
  arm64-v8a)
    printf '%s\n' "$HEADER" | grep -qE 'Machine:[[:space:]]+AArch64' \
      || { echo "error: libopenal.so is not ELF AArch64" >&2; exit 1; } ;;
  *) echo "error: unsupported verification architecture: $ARCH" >&2; exit 2 ;;
esac
echo "ELF machine: $ARCH"

SYMS="$("$READELF" --dyn-syms "$OUT/libopenal.so")"
printf '%s\n' "$SYMS" | grep -qE 'GLOBAL[[:space:]]+DEFAULT[[:space:]]+[^[:space:]]+[[:space:]]+alcOpenDevice(@|$)' \
  || { echo "error: alcOpenDevice is not exported" >&2; exit 1; }
ALC_COUNT=$(printf '%s\n' "$SYMS" | grep -cE 'GLOBAL[[:space:]]+DEFAULT[[:space:]]+[^[:space:]]+[[:space:]]+alc[A-Za-z0-9_]*(@|$)' || true)
AL_COUNT=$(printf '%s\n' "$SYMS" | grep -cE 'GLOBAL[[:space:]]+DEFAULT[[:space:]]+[^[:space:]]+[[:space:]]+al[A-Za-z0-9_]*(@|$)' || true)
[ "$ALC_COUNT" -gt 0 ] || { echo "error: no ALC symbols exported (visibility bug)" >&2; exit 1; }
echo "exported symbols: alcOpenDevice; ALC=$ALC_COUNT; AL=$AL_COUNT"

DEPS="$("$READELF" -d "$OUT/libopenal.so")"
for dep in libohaudio.so libhilog_ndk.z.so libc++_shared.so libc.so; do
  printf '%s\n' "$DEPS" | grep -qF "Shared library: [$dep]" \
    || { echo "error: required dependency missing: $dep" >&2; exit 1; }
done
echo "DT_NEEDED:"
printf '%s\n' "$DEPS" | grep 'Shared library:'

# OpenSL is intentionally dlopen'ed by upstream (HAVE_DYNLOAD), so it has no
# DT_NEEDED entry. Confirm both backends were selected in the generated config.
for backend in HAVE_OPENSL HAVE_OHAUDIO; do
  grep -qE "^#define ${backend} 1$" "$BUILD/config_backends.h" \
    || { echo "error: backend not enabled: $backend" >&2; exit 1; }
done
echo "backends: OHAudio (default), OpenSL (dlopen fallback)"

# Keep upstream licensing with the binary and retain the pinned source archive
# and patched source tree beside this scratch output.
cp "$SRC/COPYING" "$OUT/COPYING"
cp "$SRC/LICENSE-pffft" "$OUT/LICENSE-pffft"

echo "OK -> $OUT/libopenal.so ($(wc -c < "$OUT/libopenal.so") bytes)"
sha256sum "$OUT/libopenal.so"
