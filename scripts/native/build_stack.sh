#!/bin/sh
# Copyright (C) 2026 MC4HOS Contributors
# SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Build the pinned LWJGL/OpenAL stack and stage it for the entry module.
#
# Usage:
#   sh build_stack.sh --sdk-native DIR [--work DIR] [--out DIR]
#                     [--api N] [--abi arm64-v8a|x86_64] [--ninja FILE]
#
# --out defaults to the repository's entry module; --work defaults to
# .build/native-stack. Java runtimes and FreeType are packaged separately by
# scripts/bundle_jre_natives.py.

set -eu

native_pwd() { pwd -W 2>/dev/null || pwd; }
native_path() { cygpath -m "$1" 2>/dev/null || printf '%s\n' "$1"; }
HERE="$(cd "$(dirname "$0")" && native_pwd)"
ROOT="$(cd "$HERE/../.." && native_pwd)"

SDK_NATIVE=""
WORK=""
OUT=""
API=23
NINJA=ninja
ABIS=""
LWJGL_VERSION=3.4.3
LWJGL_COMMIT=30fac9b95f99cda97312232be25ba55297bf9951
LIBFFI_COMMIT=12ffd1f9dc56fcea79d2f742f424301ae668d663
OPENAL_VERSION=1.24.3
OPENAL_URL="https://github.com/kcat/openal-soft/archive/refs/tags/1.24.3.tar.gz"
OPENAL_SHA256=7e1fecdeb45e7f78722b776c5cf30bd33934b961d7fd2a11e0494e064cc631ce

usage() {
  sed -n '2,/^set -eu/p' "$0" | sed 's/^# \{0,1\}//; /^set -eu/d'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --sdk-native) SDK_NATIVE="$2"; shift 2 ;;
    --work) WORK="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --api) API="$2"; shift 2 ;;
    --ninja) NINJA="$2"; shift 2 ;;
    --abi)
      case "$2" in arm64-v8a|x86_64) ;; *) echo "error: unsupported ABI: $2" >&2; exit 2 ;; esac
      if [ -z "$ABIS" ]; then ABIS="$2"; else ABIS="$ABIS $2"; fi
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -n "$ABIS" ] || ABIS="arm64-v8a x86_64"

[ -n "$SDK_NATIVE" ] || {
  echo "error: --sdk-native is required (OHOS SDK native directory)" >&2
  usage >&2
  exit 2
}
[ -n "$WORK" ] || WORK="$ROOT/.build/native-stack"
[ -n "$OUT" ] || OUT="$ROOT/entry"
mkdir -p "$WORK" "$OUT"
WORK="$(cd "$WORK" && native_pwd)"
OUT="$(cd "$OUT" && native_pwd)"
SDK_NATIVE="$(native_path "$SDK_NATIVE")"

for tool in git curl cmake python3 javac jar tar unzip sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "error: required tool not found on PATH: $tool" >&2
    exit 2
  }
done
if [ ! -f "$NINJA" ] && ! command -v "$NINJA" >/dev/null 2>&1; then
  echo "error: Ninja not found: $NINJA (use --ninja FILE)" >&2
  exit 2
fi
[ -f "$SDK_NATIVE/build/cmake/ohos.toolchain.cmake" ] || {
  echo "error: not an OHOS SDK native directory: $SDK_NATIVE" >&2
  exit 2
}

fetch_commit() {
  repo="$1"; commit="$2"; dest="$3"
  if [ -d "$dest/.git" ] && [ "$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)" = "$commit" ]; then
    [ -z "$(git -C "$dest" status --porcelain)" ] || {
      echo "error: cached source has local changes: $dest" >&2
      echo "       choose a clean --work directory or remove that managed checkout" >&2
      exit 1
    }
    echo "  source ready: $dest ($commit)"
    return
  fi
  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  git init -q "$dest"
  git -C "$dest" fetch -q --depth 1 "$repo" "$commit"
  git -C "$dest" checkout -q --detach FETCH_HEAD
  [ "$(git -C "$dest" rev-parse HEAD)" = "$commit" ] || {
    echo "error: fetched revision mismatch for $repo" >&2
    exit 1
  }
}

fetch_archive() {
  url="$1"; dest="$2"; expected="$3"
  if [ ! -f "$dest" ]; then
    mkdir -p "$(dirname "$dest")"
    curl --fail --location --retry 3 --connect-timeout 20 \
      --output "$dest.part" "$url"
    mv "$dest.part" "$dest"
  fi
  actual="$(sha256sum "$dest" | cut -d' ' -f1)"
  [ "$actual" = "$expected" ] || {
    echo "error: SHA-256 mismatch for $dest" >&2
    echo "  expected $expected" >&2
    echo "  actual   $actual" >&2
    exit 1
  }
}

LWJGL_SRC="$WORK/src/lwjgl3-$LWJGL_VERSION"
LIBFFI_SRC="$WORK/src/libffi-3.8.0"
OPENAL_ARCHIVE="$WORK/downloads/openal-soft-$OPENAL_VERSION.tar.gz"

echo "=== fetch pinned native sources ==="
fetch_commit "https://github.com/LWJGL/lwjgl3.git" "$LWJGL_COMMIT" "$LWJGL_SRC"
fetch_commit "https://github.com/libffi/libffi.git" "$LIBFFI_COMMIT" "$LIBFFI_SRC"
fetch_archive "$OPENAL_URL" "$OPENAL_ARCHIVE" "$OPENAL_SHA256"

echo "=== build adapted LWJGL $LWJGL_VERSION JAR ==="
sh "$(native_path "$HERE/lwjgl/build_lwjgl_jar.sh")" \
  --version "$LWJGL_VERSION" \
  --work "$(native_path "$WORK/jar")" \
  --out "$(native_path "$WORK/jar-out")" \
  --cache "$(native_path "$WORK/maven")" \
  --pack-jar "$(native_path "$HERE/lwjgl/pack_jar.py")"
mkdir -p "$OUT/src/main/resources/rawfile/bridge"
cp "$WORK/jar-out/lwjgl.jar" "$OUT/src/main/resources/rawfile/bridge/lwjgl-$LWJGL_VERSION.jar"

for abi in $ABIS; do
  echo "=== build game natives ($abi, API $API) ==="
  lwjgl_out="$WORK/out/$abi/lwjgl"
  mkdir -p "$lwjgl_out" "$OUT/libs/$abi"
  sh "$(native_path "$HERE/lwjgl/build_lwjgl_natives.sh")" \
    --src "$(native_path "$LWJGL_SRC")" \
    --sdk-native "$SDK_NATIVE" \
    --out "$(native_path "$lwjgl_out")" \
    --build "$(native_path "$WORK/build/$abi/lwjgl")" \
    --jni-inc "$(native_path "$ROOT/entry/src/main/cpp/meowcraftbridge")" \
    --libffi-src "$(native_path "$LIBFFI_SRC")" \
    --generation "$LWJGL_VERSION" \
    --arch "$abi" --api "$API"

  openal_src="$WORK/src/openal-$abi"
  rm -rf "$openal_src"
  mkdir -p "$openal_src"
  tar -xzf "$OPENAL_ARCHIVE" -C "$openal_src"
  openal_root="$openal_src/openal-soft-$OPENAL_VERSION"
  openal_out="$WORK/out/$abi/openal"
  mkdir -p "$openal_out"
  sh "$(native_path "$HERE/openal/build_openal_meow.sh")" \
    --src "$(native_path "$openal_root")" \
    --sdk-native "$SDK_NATIVE" \
    --out "$(native_path "$openal_out")" \
    --build "$(native_path "$WORK/build/$abi/openal")" \
    --patcher "$(native_path "$HERE/openal/patch_openal_ohos.py")" \
    --ohaudio-patcher "$(native_path "$HERE/openal/patch_openal_ohaudio.py")" \
    --events-patcher "$(native_path "$HERE/openal/patch_openal_events_export.py")" \
    --ninja "$(native_path "$NINJA")" \
    --arch "$abi" --api "$API"

  for lib in liblwjgl_343.so liblwjgl_343_opengl.so liblwjgl_343_stb.so liblwjgl_tinyfd.so; do
    cp "$lwjgl_out/$lib" "$OUT/libs/$abi/$lib"
  done
  cp "$openal_out/libopenal.so" "$OUT/libs/$abi/libopenal.so"
done

echo "OK -> $OUT/libs/{arm64-v8a,x86_64} and $OUT/src/main/resources/rawfile/bridge/lwjgl-$LWJGL_VERSION.jar"
