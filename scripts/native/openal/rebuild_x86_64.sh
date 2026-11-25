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

# Clean, pinned scratch rebuild of OpenAL Soft 1.24.3 for HarmonyOS x86_64.
# No project files or entry/libs outputs are touched.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
BASE="$ROOT/.build/openal-x86_64"
BASE_WIN="$(cygpath -m "$BASE")"
SDK="${OHOS_SDK_NATIVE:-C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/native}"

SOURCE_URL="https://github.com/kcat/openal-soft/archive/refs/tags/1.24.3.tar.gz"
SOURCE_SHA256="7e1fecdeb45e7f78722b776c5cf30bd33934b961d7fd2a11e0494e064cc631ce"
NINJA_URL="https://github.com/ninja-build/ninja/releases/download/v1.12.1/ninja-win.zip"
NINJA_SHA256="f550fec705b6d6ff58f2db3c374c2277a37691678d6aba463adcbb129108467a"

SRC_ARCHIVE="$BASE/src/openal-soft-1.24.3.tar.gz"
SRC="$BASE/src/openal-soft-1.24.3"
NINJA_ZIP="$BASE/tools/ninja-win.zip"
NINJA="$BASE/tools/ninja.exe"

mkdir -p "$BASE/src" "$BASE/tools" "$BASE/out"

if [ ! -f "$SRC_ARCHIVE" ]; then
  curl --fail --location --silent --show-error "$SOURCE_URL" --output "$SRC_ARCHIVE"
fi
ACTUAL="$(sha256sum "$SRC_ARCHIVE")"
ACTUAL="${ACTUAL%% *}"
[ "$ACTUAL" = "$SOURCE_SHA256" ] || {
  echo "error: OpenAL source archive SHA-256 mismatch: $ACTUAL" >&2
  exit 1
}

if [ ! -f "$NINJA_ZIP" ]; then
  curl --fail --location --silent --show-error "$NINJA_URL" --output "$NINJA_ZIP"
fi
ACTUAL="$(sha256sum "$NINJA_ZIP")"
ACTUAL="${ACTUAL%% *}"
[ "$ACTUAL" = "$NINJA_SHA256" ] || {
  echo "error: Ninja archive SHA-256 mismatch: $ACTUAL" >&2
  exit 1
}
python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' \
  "$NINJA_ZIP" "$BASE/tools"

# Always patch a fresh extraction; the upstream patchers are intentionally not
# idempotent. The verified archive remains cached for offline rebuilds.
rm -rf "$SRC"
tar -xzf "$SRC_ARCHIVE" -C "$BASE/src"

exec sh "$HERE/build_openal_meow.sh" \
  --src "$BASE_WIN/src/openal-soft-1.24.3" \
  --sdk-native "$SDK" \
  --out "$BASE_WIN/out" \
  --build "$BASE_WIN/build" \
  --arch x86_64 \
  --api 23 \
  --ninja "$NINJA"
