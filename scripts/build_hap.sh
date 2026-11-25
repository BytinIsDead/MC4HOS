#!/usr/bin/env bash
# Copyright (C) 2026 MC4HOS Contributors
# SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Builds the HAP locally using the DevEco Studio installation (or the
# standalone commandline-tools package) on this machine — no repository
# variables, no secrets. Runtime packs are fetched at build time and bundled
# inside the HAP; set BUNDLE_JRES=0 to build without them. The pinned
# LWJGL/OpenAL stack must already be staged by scripts/native/build_stack.sh.
# Windows users: use build_hap.bat.
#
# Override the install location with:  export DEVECO_STUDIO_HOME=<dir>

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "${DEVECO_STUDIO_HOME:-}" ]; then
  for candidate in \
    "/Applications/DevEco-Studio.app/Contents" \
    "$HOME/commandline-tools" \
    "$HOME/hos-tools/commandline-tools" \
    "/opt/harmonyos/commandline-tools"; do
    if [ -f "$candidate/tools/hvigor/bin/hvigorw.js" ]; then
      DEVECO_STUDIO_HOME="$candidate"
      break
    fi
  done
fi

if [ -z "${DEVECO_STUDIO_HOME:-}" ] || [ ! -f "$DEVECO_STUDIO_HOME/tools/hvigor/bin/hvigorw.js" ]; then
  echo "ERROR: DevEco Studio / commandline-tools not found."
  echo "       Set DEVECO_STUDIO_HOME to the install directory and retry."
  exit 1
fi
echo "DevEco Studio: $DEVECO_STUDIO_HOME"

NODE_BIN="$DEVECO_STUDIO_HOME/tools/node/bin/node"
[ -x "$NODE_BIN" ] || NODE_BIN="$(command -v node)"
HVIGORW_JS="$DEVECO_STUDIO_HOME/tools/hvigor/bin/hvigorw.js"
export DEVECO_SDK_HOME="$DEVECO_STUDIO_HOME/sdk"

# dependencies (skip gracefully when ohpm is absent but oh_modules exists)
OHPM="$DEVECO_STUDIO_HOME/tools/ohpm/bin/ohpm"
if [ -x "$OHPM" ]; then
  echo "Running ohpm install..."
  "$OHPM" install
elif [ -d "$ROOT/oh_modules" ]; then
  echo "[warn] ohpm not found - using existing oh_modules"
else
  echo "ERROR: ohpm not found and no oh_modules present"
  exit 1
fi

cd "$ROOT"
if [ "${BUNDLE_JRES:-1}" != "0" ]; then
  echo "Fetching bundled Java runtimes (set BUNDLE_JRES=0 to skip)..."
  python3 "$ROOT/scripts/fetch_bundled_jres.py" \
    --dest "$ROOT/entry/src/main/resources/rawfile/jvm"
  echo "Packaging JRE native libraries into entry/libs (<abi>/libjvm.so)..."
  python3 "$ROOT/scripts/bundle_jre_natives.py"
fi

echo "Building MC4HOS bridge jar..."
python3 "$ROOT/scripts/build_bridge_jar.py"

echo "Verifying staged native stack..."
python3 "$ROOT/scripts/check_native_stack.py" --entry "$ROOT/entry"

mkdir -p .build
echo "Building HAP (debug, unsigned)..."
set +e
"$NODE_BIN" "$HVIGORW_JS" --mode module -p module=entry@default -p product=default assembleHap \
  2>&1 | tee .build/hvigor-build.log
BUILD_EXIT=${PIPESTATUS[0]}
set -e
if [ "$BUILD_EXIT" -ne 0 ] || grep -q "BUILD FAILED" .build/hvigor-build.log; then
  echo "ERROR: hvigor build failed (exit $BUILD_EXIT)" >&2
  exit 1
fi
if ! grep -q "BUILD SUCCESSFUL" .build/hvigor-build.log; then
  echo "ERROR: hvigor produced no BUILD SUCCESSFUL marker" >&2
  exit 1
fi

mkdir -p out
find entry/build -name "*.hap" -exec cp {} out/ \;
echo
echo "Done. HAP file(s):"
ls -la out/*.hap
