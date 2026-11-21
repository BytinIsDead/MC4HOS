#!/usr/bin/env bash
# Copyright (C) 2026 MC4HOS Contributors
# SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Cross-compiles OpenJDK 21/25 for x86_64-linux-ohos (musl) and packages a
# complete runtime zip. Requires a Linux x86_64 host. See README.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TREE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

MAJOR="${MAJOR:-21}"
OHOS_NATIVE="${OHOS_NATIVE:-}"
BUILD_INPUTS="${BUILD_INPUTS:-}"
WORK_DIR="${WORK_DIR:-}"
OUT_DIR="${OUT_DIR:-}"
RELEASE_BASE="${RELEASE_BASE:-}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"

die() { echo "error: $*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: build_x86_64.sh --major 21|25 --native <ohos-native> --inputs <build-inputs>
                       [--work <dir>] [--output <dir>] [--release-base <url>]

Environment:
  JAVA_HOME       Boot JDK 21 (for --major 21) or 25 (for --major 25)
  JOBS            Parallel make jobs (default: host CPU count)
  RELEASE_BASE    Optional release download base, appended with /<pack>.zip
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --major) MAJOR="$2"; shift 2 ;;
    --native) OHOS_NATIVE="$2"; shift 2 ;;
    --inputs) BUILD_INPUTS="$2"; shift 2 ;;
    --work) WORK_DIR="$2"; shift 2 ;;
    --output) OUT_DIR="$2"; shift 2 ;;
    --release-base) RELEASE_BASE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

case "$MAJOR" in
  21|25) ;;
  *) die "--major must be 21 or 25 (Java 8/17 x86_64 builds are not part of this tree)" ;;
esac
[ -n "$OHOS_NATIVE" ] || die "--native is required (…/openharmony/native)"
[ -d "$OHOS_NATIVE/sysroot" ] || die "not an OHOS native SDK: $OHOS_NATIVE"
[ -n "$BUILD_INPUTS" ] || die "--inputs is required (see scripts/fetch_inputs.py)"
[ -d "$BUILD_INPUTS/docker/stubs" ] || die "not a build-inputs tree: $BUILD_INPUTS"

OHOS_NATIVE="$(cd "$OHOS_NATIVE" && pwd)"
BUILD_INPUTS="$(cd "$BUILD_INPUTS" && pwd)"
WORK_DIR="${WORK_DIR:-$PWD/work-jdk$MAJOR}"
OUT_DIR="${OUT_DIR:-$PWD/out}"
mkdir -p "$WORK_DIR" "$OUT_DIR"
WORK_DIR="$(cd "$WORK_DIR" && pwd)"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

PATCH_DIR="$BUILD_INPUTS/prebuilt/jdk/$MAJOR/patches"
[ -f "$PATCH_DIR/series" ] || die "missing patch series: $PATCH_DIR/series"
INPUTS_JSON="$BUILD_INPUTS/prebuilt/jdk/build-inputs.json"
[ -f "$INPUTS_JSON" ] || die "missing $INPUTS_JSON"

if [ -z "${JAVA_HOME:-}" ]; then
  JAVA_BIN="$(command -v java || true)"
  [ -n "$JAVA_BIN" ] || die "JAVA_HOME is unset and no java is on PATH"
  JAVA_HOME="$(cd "$(dirname "$(readlink -f "$JAVA_BIN")")/.." && pwd)"
fi
[ -x "$JAVA_HOME/bin/java" ] || die "not a JDK: $JAVA_HOME"
BOOT_VERSION="$("$JAVA_HOME/bin/java" -version 2>&1 | awk -F'"' '/version/ {print $2; exit}')"
BOOT_MAJOR="${BOOT_VERSION%%.*}"
case "$BOOT_MAJOR" in 1) BOOT_MAJOR="$(echo "$BOOT_VERSION" | cut -d. -f2)" ;; esac
[ "${BOOT_MAJOR:-0}" -ge "$MAJOR" ] 2>/dev/null \
  || die "boot JDK is $BOOT_VERSION; JDK $MAJOR (or newer within the same line) is required"

read -r SRC_REPO SRC_COMMIT < <(python3 - "$INPUTS_JSON" "$MAJOR" <<'PY'
import json, sys
item = json.load(open(sys.argv[1], encoding="utf-8"))["runtimes"][sys.argv[2]]
print(item["repository"], item["commit"])
PY
)
[ -n "${SRC_REPO:-}" ] && [ -n "${SRC_COMMIT:-}" ] || die "source pin missing from $INPUTS_JSON"

echo "=== OpenJDK $MAJOR for x86_64-linux-ohos ==="
echo "Native SDK:  $OHOS_NATIVE"
echo "Build inputs:$BUILD_INPUTS"
echo "Work:        $WORK_DIR"
echo "Boot JDK:    $JAVA_HOME ($BOOT_VERSION)"
echo "Source:      $SRC_REPO @ $SRC_COMMIT"

# ---------------------------------------------------------------------------
# 1. Writable sysroot, arch header links, CRT/library stubs
# ---------------------------------------------------------------------------
SYSROOT="$WORK_DIR/sysroot"
SYSROOT_MARKER="$SYSROOT/.mc4hos-native"
if [ ! -d "$SYSROOT" ]; then
  mkdir -p "$SYSROOT"
  cp -a "$OHOS_NATIVE/sysroot/." "$SYSROOT/"
  printf '%s\n' "$OHOS_NATIVE" > "$SYSROOT_MARKER"
elif [ ! -f "$SYSROOT_MARKER" ] || [ "$(cat "$SYSROOT_MARKER")" != "$OHOS_NATIVE" ]; then
  die "$SYSROOT was prepared from a different SDK; use a new --work directory"
fi

ARCH="x86_64"
TRIPLE="x86_64-linux-ohos"
TARGET_LIB="$SYSROOT/usr/lib/$TRIPLE"
ARCH_INCLUDE="$SYSROOT/usr/include/$TRIPLE"
LIBCXX_INC="$OHOS_NATIVE/llvm/include/libcxx-ohos/include/c++/v1"
[ -d "$LIBCXX_INC" ] || die "missing libc++ headers: $LIBCXX_INC"
[ -d "$TARGET_LIB" ] || die "missing target lib dir: $TARGET_LIB"

[ -e "$SYSROOT/usr/include/bits" ] || ln -s "$TRIPLE/bits" "$SYSROOT/usr/include/bits"
[ -e "$SYSROOT/usr/include/asm" ] || ln -s "$TRIPLE/asm" "$SYSROOT/usr/include/asm"
for f in Scrt1.o crt1.o crti.o crtn.o; do
  [ -f "$TARGET_LIB/$f" ] || die "missing CRT object: $TARGET_LIB/$f"
  [ -e "$SYSROOT/usr/lib/$f" ] || ln -s "$TRIPLE/$f" "$SYSROOT/usr/lib/$f"
done

LLVM_BIN="$OHOS_NATIVE/llvm/bin"
llvm_tool() {
  local name="$1"
  if [ -x "$LLVM_BIN/$name" ]; then echo "$LLVM_BIN/$name"
  elif [ -x "$LLVM_BIN/$name.exe" ]; then echo "$LLVM_BIN/$name.exe"
  else die "missing LLVM tool: $name"; fi
}
CLANG="$(llvm_tool clang)"
CLANGXX="$(llvm_tool clang++)"
LLVM_AR="$(llvm_tool llvm-ar)"
LLVM_RANLIB="$(llvm_tool llvm-ranlib)"
LLVM_STRIP="$(llvm_tool llvm-strip)"
LLVM_NM="$(llvm_tool llvm-nm)"
LLVM_OBJCOPY="$(llvm_tool llvm-objcopy)"
LLVM_READELF="$(llvm_tool llvm-readelf)"
LLD="$(llvm_tool ld.lld)"

[ -f "$TARGET_LIB/libgcc.a" ] || "$LLVM_AR" rcs "$TARGET_LIB/libgcc.a"
[ -e "$TARGET_LIB/libgcc_s.so" ] || ln -s libc.so "$TARGET_LIB/libgcc_s.so"
cp -f "$OHOS_NATIVE/llvm/lib/$TRIPLE/libc++_shared.so" "$TARGET_LIB/libc++_shared.so"

# ---------------------------------------------------------------------------
# 2. Toolchain wrappers (NDK clang + musl linker)
# ---------------------------------------------------------------------------
TC="$WORK_DIR/toolchain"
mkdir -p "$TC"

cat > "$TC/$TRIPLE-gcc" <<EOF
#!/usr/bin/env bash
set -e
ARGS=()
LINK=1
OUT=0
for arg in "\$@"; do
  case "\$arg" in
    -c|-E|-S|-shared|-r) LINK=0 ;;
    -o) OUT=1 ;;
  esac
  case "\$arg" in
    -lpthread|-ldl|-lrt|-lresolv) ;;
    *) ARGS+=("\$arg") ;;
  esac
done
if [ "\$LINK" = 1 ] && [ "\$OUT" = 1 ]; then
  ARGS+=("-Wl,--dynamic-linker=/lib/ld-musl-$ARCH.so.1")
fi
exec $(printf '%q' "$CLANG") --target=$TRIPLE --sysroot=$(printf '%q' "$SYSROOT") \\
  -B$(printf '%q' "$SYSROOT/usr/lib") -B$(printf '%q' "$TARGET_LIB") \\
  -L$(printf '%q' "$TARGET_LIB") -rtlib=compiler-rt -unwindlib=none \\
  -fuse-ld=lld "\${ARGS[@]}"
EOF

cat > "$TC/$TRIPLE-g++" <<EOF
#!/usr/bin/env bash
set -e
ARGS=()
LINK=1
OUT=0
for arg in "\$@"; do
  case "\$arg" in
    -c|-E|-S|-shared|-r) LINK=0 ;;
    -o) OUT=1 ;;
  esac
  case "\$arg" in
    -lpthread|-ldl|-lrt|-lresolv) ;;
    *) ARGS+=("\$arg") ;;
  esac
done
if [ "\$LINK" = 1 ] && [ "\$OUT" = 1 ]; then
  ARGS+=("-Wl,--dynamic-linker=/lib/ld-musl-$ARCH.so.1")
fi
exec $(printf '%q' "$CLANGXX") --target=$TRIPLE --sysroot=$(printf '%q' "$SYSROOT") \\
  -B$(printf '%q' "$SYSROOT/usr/lib") -B$(printf '%q' "$TARGET_LIB") \\
  -L$(printf '%q' "$TARGET_LIB") -rtlib=compiler-rt -unwindlib=none \\
  -stdlib=libc++ -nostdlib++ -fuse-ld=lld "\${ARGS[@]}"
EOF

for spec in \
  "ar:$LLVM_AR" "ranlib:$LLVM_RANLIB" "strip:$LLVM_STRIP" \
  "nm:$LLVM_NM" "objcopy:$LLVM_OBJCOPY" "readelf:$LLVM_READELF"; do
  name="${spec%%:*}"
  bin="${spec#*:}"
  cat > "$TC/$TRIPLE-$name" <<EOF
#!/usr/bin/env bash
exec $(printf '%q' "$bin") "\$@"
EOF
done
cat > "$TC/$TRIPLE-ld" <<EOF
#!/usr/bin/env bash
exec $(printf '%q' "$LLD") "\$@"
EOF
chmod +x "$TC/$TRIPLE-"*

# ---------------------------------------------------------------------------
# 3. Stub headers, ALSA stub, C++ ABI facade
# ---------------------------------------------------------------------------
SHIM_SRC="$BUILD_INPUTS/prebuilt/stubs/src/cxxabi_shim.cpp"
[ -f "$SHIM_SRC" ] || die "missing C++ ABI facade source: $SHIM_SRC"

rm -rf "$WORK_DIR/stub-headers" "$WORK_DIR/stub-cups"
mkdir -p "$WORK_DIR/stub-headers" "$WORK_DIR/stub-cups" "$WORK_DIR/lib"
cp -a "$BUILD_INPUTS/docker/stubs/fontconfig/." "$WORK_DIR/stub-headers/"
cp -a "$BUILD_INPUTS/docker/stubs/x11/." "$WORK_DIR/stub-headers/"
cp -a "$BUILD_INPUTS/docker/stubs/cups/." "$WORK_DIR/stub-cups/"
if [ -d /usr/include/alsa ]; then
  cp -a /usr/include/alsa "$WORK_DIR/stub-headers/"
else
  echo "warning: /usr/include/alsa missing; javax.sound ALSA support will be disabled"
fi

if [ ! -f "$TARGET_LIB/libasound.so" ]; then
  printf 'void mc4hos_asound_stub(void) {}\n' > "$WORK_DIR/asound_stub.c"
  "$CLANG" --target=$TRIPLE --sysroot="$SYSROOT" -fuse-ld=lld -shared -nostdlib \
    -Wl,-soname,libasound.so.2 -o "$TARGET_LIB/libasound.so" \
    "$WORK_DIR/asound_stub.c"
  ln -sf libasound.so "$TARGET_LIB/libasound.so.2"
fi

"$CLANGXX" --target=$TRIPLE --sysroot="$SYSROOT" -shared -fPIC \
  -fvisibility=hidden -nostdlib -fuse-ld=lld "$SHIM_SRC" \
  -L"$TARGET_LIB" -Wl,--no-as-needed -lc++_shared -Wl,--as-needed -lc \
  -Wl,--no-undefined -Wl,-soname,libcxxabi_shim.so -Wl,-rpath,'$ORIGIN' \
  -o "$WORK_DIR/lib/libcxxabi_shim.so"

# ---------------------------------------------------------------------------
# 4. Pinned OpenJDK sources
# ---------------------------------------------------------------------------
SRC="$WORK_DIR/jdk${MAJOR}u"
if [ ! -d "$SRC/.git" ]; then
  [ -e "$SRC" ] && die "$SRC exists but is not a git checkout; use a new --work directory"
  git init -q "$SRC"
  git -C "$SRC" remote add origin "$SRC_REPO"
  if ! git -C "$SRC" fetch -q --depth=1 origin "$SRC_COMMIT"; then
    git -C "$SRC" fetch -q origin "$SRC_COMMIT"
  fi
  git -C "$SRC" -c advice.detachedHead=false checkout -q --detach FETCH_HEAD
else
  HEAD="$(git -C "$SRC" rev-parse HEAD)"
  [ "$HEAD" = "$SRC_COMMIT" ] \
    || die "$SRC is at $HEAD; expected $SRC_COMMIT — use a new --work directory"
fi

if git -C "$SRC" diff --quiet HEAD --; then
  echo "Applying $(grep -cvE '^[[:space:]]*(#|$)' "$PATCH_DIR/series") OHOS patches"
  while IFS= read -r patch; do
    case "$patch" in ''|'#'*) continue ;; esac
    git -C "$SRC" apply --check "$PATCH_DIR/$patch"
    git -C "$SRC" apply "$PATCH_DIR/$patch"
  done < "$PATCH_DIR/series"
else
  echo "Source tree already modified; skipping patch application"
fi

# ---------------------------------------------------------------------------
# 5. Configure and build
# ---------------------------------------------------------------------------
COMMON_FLAGS="--target=$TRIPLE --sysroot=$SYSROOT -fPIC \
-D__OHOS__=1 -D__OHOS_FAMILY__=1 -D__OHOS_Major__=0 -D__MUSL__ -DMUSL_LIBC \
$ARCH_INCLUDE -I$WORK_DIR/stub-headers -isystem $LIBCXX_INC \
-B$TARGET_LIB -L$TARGET_LIB -rtlib=compiler-rt -unwindlib=none"
if [ -d "$BUILD_INPUTS/prebuilt/jdk/$MAJOR/shims" ]; then
  COMMON_FLAGS="-I$BUILD_INPUTS/prebuilt/jdk/$MAJOR/shims $COMMON_FLAGS"
fi
EXTRA_CXXFLAGS="$COMMON_FLAGS -stdlib=libc++ -nostdlib++ -nostdinc++"
EXTRA_LDFLAGS="--target=$TRIPLE --sysroot=$SYSROOT -fuse-ld=lld \
-B$TARGET_LIB -L$TARGET_LIB -rtlib=compiler-rt -unwindlib=none \
-nostdlib++ -L$WORK_DIR/lib -lcxxabi_shim -lc++_shared"

export SOURCE_DATE_EPOCH="$(git -C "$SRC" log -1 --format=%ct)"
export PATH="$TC:$PATH"

cd "$SRC"
echo "=== configure ==="
bash configure \
  --build=x86_64-unknown-linux-gnu \
  --openjdk-target=x86_64-unknown-linux-musl \
  --with-jvm-variants=server \
  --with-debug-level=release \
  --with-native-debug-symbols=none \
  --with-boot-jdk="$JAVA_HOME" \
  --with-extra-cflags="$COMMON_FLAGS" \
  --with-extra-cxxflags="$EXTRA_CXXFLAGS" \
  --with-extra-ldflags="$EXTRA_LDFLAGS" \
  --x-includes=/dev/null \
  --x-libraries=/dev/null \
  --with-cups-include="$WORK_DIR/stub-cups" \
  --with-freetype=bundled \
  --enable-headless-only \
  --disable-warnings-as-errors \
  --with-toolchain-type=clang \
  CC="$TC/$TRIPLE-gcc" \
  CXX="$TC/$TRIPLE-g++" \
  CPP="$TC/$TRIPLE-gcc -E $ARCH_INCLUDE -I$WORK_DIR/stub-headers --target=$TRIPLE --sysroot=$SYSROOT" \
  CXXCPP="$TC/$TRIPLE-g++ -E $ARCH_INCLUDE -I$WORK_DIR/stub-headers --target=$TRIPLE --sysroot=$SYSROOT" \
  AR="$TC/$TRIPLE-ar" \
  STRIP="$TC/$TRIPLE-strip" \
  NM="$TC/$TRIPLE-nm" \
  OBJCOPY="$TC/$TRIPLE-objcopy" \
  BUILD_CC="$(command -v gcc)" \
  BUILD_CXX="$(command -v g++)" \
  2>&1 | tee "$WORK_DIR/configure-$MAJOR.log"

echo "=== make images (JOBS=$JOBS) ==="
make images JOBS="$JOBS" 2>&1 | tee "$WORK_DIR/build-$MAJOR.log"

IMAGE="$SRC/build/linux-x86_64-server-release/images/jdk"
[ -f "$IMAGE/release" ] && [ -f "$IMAGE/lib/modules" ] \
  && [ -f "$IMAGE/lib/server/libjvm.so" ] \
  || die "missing final image at $IMAGE"

# ---------------------------------------------------------------------------
# 6. Package
# ---------------------------------------------------------------------------
cp -f "$TARGET_LIB/libc++_shared.so" "$IMAGE/lib/"
cp -f "$WORK_DIR/lib/libcxxabi_shim.so" "$IMAGE/lib/"

PACK_NAME="jre${MAJOR}-ohos-x86_64"
STAGE="$WORK_DIR/stage/$PACK_NAME"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -a "$IMAGE/." "$STAGE/"

for f in LICENSE ADDITIONAL_LICENSE_INFO ASSEMBLY_EXCEPTION; do
  [ -f "$SRC/$f" ] && cp "$SRC/$f" "$STAGE/"
done
mkdir -p "$STAGE/legal/amcl-native"
cp "$OHOS_NATIVE/NOTICE.txt" "$STAGE/legal/amcl-native/NOTICE.txt"
cat > "$STAGE/MC4HOS-RUNTIME-NOTICE.txt" <<NOTICE
MC4HOS x86_64 OpenJDK runtime pack

OpenJDK ${MAJOR}u is licensed under GPLv2 with the Classpath Exception.
Upstream source: $SRC_REPO
Upstream commit: $SRC_COMMIT

OHOS patches, stub headers, and the C++ ABI facade were obtained from the
build-inputs archive pinned in openharmony-jdk/build-inputs.lock.json.
The archive is GPLv2+CE material and is not part of this repository.

The pack also contains libc++_shared.so and NOTICE.txt from the HarmonyOS
SDK (Apache-2.0 WITH LLVM-exception and the SDK's own notices).

Redistributors must preserve these notices and provide the corresponding
source as required by GPLv2.
NOTICE

ZIP="$OUT_DIR/$PACK_NAME.zip"
rm -f "$ZIP"
(cd "$STAGE" && zip -qry "$ZIP" .)
[ -s "$ZIP" ] || die "packaging failed: $ZIP"

PACK_URL=""
if [ -n "$RELEASE_BASE" ]; then
  PACK_URL="${RELEASE_BASE%/}/$PACK_NAME.zip"
fi
python3 "$SCRIPT_DIR/write_catalog.py" --major "$MAJOR" --zip "$ZIP" \
  --out "$OUT_DIR/runtime-catalog-$MAJOR.json" --url "$PACK_URL"

echo ""
echo "=== DONE ==="
echo "Pack:    $ZIP"
echo "Catalog: $OUT_DIR/runtime-catalog-$MAJOR.json"
sha256sum "$ZIP"
