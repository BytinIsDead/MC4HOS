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

# Build Meowcraft's OHOS lwjgl.jar from official LWJGL <ver> jars + clean-room GLFW overlay.
#
# This is the "jar" half of the lwjgl self-build (the natives half is
# build_lwjgl_natives.sh). It reproduces the shipped fat lwjgl.jar recipe:
#
#   official LWJGL modules (12)  +  clean-room GLFW overlay (~20 java files)
#   -> one merged jar, META-INF/cacio stripped, overlay wins on collisions.
#
# The overlay lives in tools/lwjgl/deltas/overlay; its RendererInit class matches
# our own bridge export Java_org_lwjgl_opengl_RendererInit_nativeInitGl4esInternals
# (see libs/meowcraftlib/src/main/cpp/meowcraftbridge/input_bridge.c).
#
# Standalone: every path is passed in, nothing is derived from the caller layout.
#
# Usage:
#   sh build_lwjgl_jar.sh --overlay DIR [--overlay DIR2 ...] [--official DIR]
#                         [--out DIR] [--work DIR] [--version 3.4.3] [--cache DIR]
#                         [--maven-base URL] [--offline] [--pack-jar FILE] [--manifest FILE]
#
# The official LWJGL modules are pulled from Maven Central (release, sha1-verified)
# and cached, so the stock base is the verifiable Maven RELEASE by default (stronger
# provenance than the historical 3.3.3-snapshot). Same "download if missing" pattern as
# tools/oshi.
#
# Required:
#   --overlay DIR    overlay source root (org/lwjgl/**); repeatable, applied in order
#                    (later wins). default <this dir>/deltas/overlay (common
#                    clean-room overlay). For a per-generation jar add the matching
#                    version overlay, e.g. --overlay deltas/overlay --overlay
#                    deltas/overlay-3.4.3 --version 3.4.3
# Optional:
#   --official DIR   local fallback dir for stock jars (also source of lwjglx, see below)
#   --out DIR        output dir for lwjgl.jar (default <work>/out)
#   --work DIR       scratch dir (default: ${TMPDIR:-/tmp}/lwjgl_build-<version>)
#   --version VER    LWJGL version to fetch (default 3.4.3)
#   --cache DIR      Maven cache dir (default <work>/m2)
#   --maven-base URL Maven repo base (default Maven Central)
#   --offline        never download; require every jar under --official
#   --with-lwjglx    ALSO merge lwjgl-lwjglx (LWJGL2 compat; DEFAULT: dropped)
#   --pack-jar FILE  deterministic packer (default ../oshi/pack_jar.py)
#   --manifest FILE  MANIFEST.MF to embed (default: extract from the core module jar)
#   -h, --help       show this help
#
# NB: `lwjgl-lwjglx` (LWJGL2 compat, NOT on Maven Central) is DROPPED by default:
# MC >= 1.17 does not reference any of its 163 unique classes (verified by scanning
# MC 1.21.10 + all MC libs). Use --with-lwjglx to include it.
#
# Requires a working JDK. JDK 8 uses -source/-target 8; newer JDKs use --release 8.
# The merge/pack steps are pure python/shell and reproducible.
set -e

# Windows Java cannot interpret Git Bash's /c/... paths in classpaths/argfiles.
native_pwd() { pwd -W 2>/dev/null || pwd; }
HERE="$(cd "$(dirname "$0")" && native_pwd)"
ROOT="$(cd "$HERE/../.." && native_pwd)"        # Meowcraft/ (app project)
# Git Bash launches Windows Java, whose classpath separator is ';', not ':'.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) CP_SEP=';' ;;
  *)                   CP_SEP=':' ;;
esac

usage() { sed -n '2,/^set -e/p' "$0" | sed 's/^# \{0,1\}//; /^set -e/d'; }

OFFICIAL=""; OVERLAYS=""; OUT=""; WORK=""; VERSION="3.4.3"; WITH_LWJGLX=0
CACHE=""; MAVEN_BASE="https://repo1.maven.org/maven2"; OFFLINE=0
PACK_JAR="$HERE/pack_jar.py"; MANIFEST=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --official)   OFFICIAL="$2";   shift 2 ;;
    --overlay)    OVERLAYS="$OVERLAYS $2"; shift 2 ;;
    --out)        OUT="$2";        shift 2 ;;
    --work)       WORK="$2";       shift 2 ;;
    --version)    VERSION="$2";    shift 2 ;;
    --cache)      CACHE="$2";      shift 2 ;;
    --maven-base) MAVEN_BASE="$2"; shift 2 ;;
    --offline)    OFFLINE=1;       shift ;;
    --with-lwjglx) WITH_LWJGLX=1;  shift ;;
    --pack-jar)   PACK_JAR="$2";   shift 2 ;;
    --manifest)   MANIFEST="$2";   shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -n "$OVERLAYS" ] || OVERLAYS="$HERE/overlay $HERE/overlay-$VERSION"
for d in $OVERLAYS; do
  [ -d "$d" ] || { echo "error: overlay not a dir: $d" >&2; exit 2; }
done
[ -z "$OFFICIAL" ] || [ -d "$OFFICIAL" ] || { echo "error: not a dir: $OFFICIAL" >&2; exit 2; }
# resolve to absolute paths, preserving order (later overlays win on collisions)
ABS_OVERLAYS=""
for d in $OVERLAYS; do ABS_OVERLAYS="$ABS_OVERLAYS $(cd "$d" && native_pwd)"; done
OVERLAYS="$ABS_OVERLAYS"
FIRST_OVERLAY="${OVERLAYS# }"; FIRST_OVERLAY="${FIRST_OVERLAY%% *}"
# Guard: a per-generation overlay (overlay-<VERSION>) carries the version-pinned
# GLFW.java / GLCapabilities.java (and the 3.4.x compat shims). It MUST be passed;
# otherwise the merge silently falls back to stock classes. In this standalone
# scratch copy the overlay may live outside $HERE, so detect the passed path.
GEN_OVERLAY=""
for d in $OVERLAYS; do
  case "$d" in */overlay-$VERSION) GEN_OVERLAY="$d" ;; esac
done
[ -n "$GEN_OVERLAY" ] || {
  echo "error: no per-generation overlay for $VERSION was passed" >&2
  echo "       add: --overlay <dir>/overlay-$VERSION" >&2; exit 2; }
[ -n "$OFFICIAL" ] && OFFICIAL="$(cd "$OFFICIAL" && native_pwd)"
[ -n "$WORK" ]  || WORK="${TMPDIR:-/tmp}/lwjgl_build-$VERSION"
[ -n "$OUT" ]   || OUT="$WORK/out"
[ -n "$CACHE" ] || CACHE="$WORK/m2"
mkdir -p "$WORK" "$OUT" "$CACHE"
WORK="$(cd "$WORK" && native_pwd)"; OUT="$(cd "$OUT" && native_pwd)"; CACHE="$(cd "$CACHE" && native_pwd)"
# reset scratch BEFORE fetching (so the cache, under $WORK, is not wiped after)
rm -rf "$WORK/overlay" "$WORK/classes" "$WORK/merge"
mkdir -p "$WORK/overlay" "$WORK/classes" "$WORK/merge"

# 8 Maven-published modules (LWJGL $VERSION). Dropped as proven dead for MC <= 1.21.x
# (verified by scanning MC 1.21.10 + all MC libs = 259 jars):
#   - lwjgl-lwjglx       (LWJGL2 compat, 163 unique classes, 0 refs; --with-lwjglx re-adds)
#   - nanovg/vma/shaderc/spvc (Vulkan/2D helpers, 0 refs for MC <= 1.21.x)
# MC >= 26.3's new `renderpearl` frontend DOES use vma/spvc/shaderc (shader compile /
# reflection / Vulkan memory) and SDL3, so for LWJGL >= 3.4.x we re-add them (see below).
MODULES="lwjgl lwjgl-glfw lwjgl-opengl lwjgl-openal lwjgl-stb \
lwjgl-vulkan lwjgl-freetype lwjgl-tinyfd"
# LWJGL >= 3.4.x additions (MC >= 26.3): SDL3 (dropped GLFW), plus renderpearl's
# vma/spvc/shaderc bindings. Their natives ship separately (libSDL3.so; shaderc/spvc/vma
# only if the GL path actually calls them).
WITH_SDL=0
case "$VERSION" in
  3.4.*|4.*) MODULES="$MODULES lwjgl-sdl lwjgl-vma lwjgl-spvc lwjgl-shaderc"; WITH_SDL=1 ;;
esac

# resolve_maven <group-path> <artifact> <version> -> path | empty
# Maven (release) wins; --official is the offline / not-on-Maven fallback. Verifies
# the published .sha1 (same "download if missing" spirit as tools/oshi).
resolve_maven() {
  gp="$1"; art="$2"; ver="$3"
  dest="$CACHE/$gp/$art/$ver/$art-$ver.jar"
  if [ "$OFFLINE" != "1" ] && [ ! -s "$dest" ]; then
    mkdir -p "$(dirname "$dest")"
    echo "  fetch $art-$ver.jar ..." >&2
    code=$(curl -sL --max-time 180 --retry 3 -w '%{http_code}' -o "$dest" \
             "$MAVEN_BASE/$gp/$art/$ver/$art-$ver.jar" 2>/dev/null || echo 000)
    magic=$(dd if="$dest" bs=1 count=2 2>/dev/null)
    if [ "$code" != "200" ] || [ "$magic" != "PK" ]; then
      echo "  - $art-$ver.jar: not on Maven (http $code) -> fallback" >&2
      rm -f "$dest"
    else
      want=$(curl -sL --max-time 60 "$MAVEN_BASE/$gp/$art/$ver/$art-$ver.jar.sha1" 2>/dev/null | tr -dc '0-9a-fA-F' | cut -c1-40)
      got=$(sha1sum "$dest" 2>/dev/null | cut -d' ' -f1)
      if [ "$want" != "$got" ]; then
        echo "  ! $art-$ver.jar: sha1 mismatch (want=$want got=$got)" >&2
        rm -f "$dest"
      else
        echo "  ok $art-$ver.jar sha1=$got" >&2
      fi
    fi
  fi
  if [ -s "$dest" ]; then echo "$dest"; return; fi
  if [ -n "$OFFICIAL" ] && [ -s "$OFFICIAL/$art.jar" ]; then echo "$OFFICIAL/$art.jar"; return; fi
  echo ""
}

echo "=== resolve stock modules (release $VERSION from Maven${OFFICIAL:+; fallback $OFFICIAL}) ==="
MODULE_PATHS=""; CP=""
for a in $MODULES; do
  p="$(resolve_maven org/lwjgl "$a" "$VERSION")"
  [ -n "$p" ] || { echo "error: cannot resolve org.lwjgl:$a:$VERSION (need network or --official)" >&2; exit 2; }
  MODULE_PATHS="$MODULE_PATHS $p"; CP="$CP$CP_SEP$p"
done
# lwjgl-lwjglx is never on Maven and is dropped by default (dead for MC >= 1.17).
# Opt in with --with-lwjglx, resolved from --official, else the overlay's libs/ sibling.
if [ "$WITH_LWJGLX" != "1" ]; then
  echo "  lwjgl-lwjglx: dropped (dead for MC >= 1.17; --with-lwjglx to include)" >&2
else
  LWJGLX=""
  if [ -n "$OFFICIAL" ] && [ -s "$OFFICIAL/lwjgl-lwjglx.jar" ]; then
    LWJGLX="$OFFICIAL/lwjgl-lwjglx.jar"
  else
    LWJGLX="$(ls "$FIRST_OVERLAY/../../../../libs"/*/lwjgl-lwjglx.jar 2>/dev/null | head -1)"
  fi
  if [ -n "$LWJGLX" ]; then MODULE_PATHS="$MODULE_PATHS $LWJGLX"; CP="$CP$CP_SEP$LWJGLX"
  else echo "  note: --with-lwjglx but jar not found (not on Maven; pass --official) -> skipped" >&2; fi
fi
CP="${CP#"$CP_SEP"}"
CORE_JAR="$(resolve_maven org/lwjgl lwjgl "$VERSION")"
JSR="$(resolve_maven com/google/code/findbugs jsr305 3.0.2)"
# LWJGL 3.4.x marks its public API with org.jspecify annotations; javac needs the
# jar on the classpath to read those signatures (our overlay does not import them).
JSPECIFY="$(resolve_maven org/jspecify jspecify 1.0.0)"
echo "  merged modules: $(echo $MODULE_PATHS | wc -w)   compile cp jars: $(echo "$CP" | tr "$CP_SEP" '\n' | grep -c .)"

echo "=== 1/5 stage overlay ==="
for d in $OVERLAYS; do cp -R "$d/." "$WORK/overlay/"; done

echo "=== 2/5 javac overlay ==="
[ -n "$JSR" ] && [ -f "$JSR" ] && CP="$CP$CP_SEP$JSR"
[ -n "$JSPECIFY" ] && [ -f "$JSPECIFY" ] && CP="$CP$CP_SEP$JSPECIFY"
find "$WORK/overlay" -name '*.java' | LC_ALL=C sort > "$WORK/sources.txt"
echo "  overlay sources: $(wc -l < "$WORK/sources.txt")  cp: $(echo "$CP" | tr "$CP_SEP" '\n' | wc -l) jars"
if ! javac -version >/dev/null 2>&1; then
  echo "[NO USABLE JVM] javac is unavailable; run with a working JDK" >&2
  exit 3
fi
JAVAC_VERSION="$(javac -version 2>&1)"
case "$JAVAC_VERSION" in
  javac\ 1\.8.*)
    javac -encoding UTF-8 -source 8 -target 8 -nowarn -g:none -cp "$CP" \
      -d "$WORK/classes" @"$WORK/sources.txt" ;;
  *)
    javac -encoding UTF-8 --release 8 -XDignore.symbol.file -proc:none -nowarn -g:none \
      -cp "$CP" -d "$WORK/classes" @"$WORK/sources.txt" || \
    javac -encoding UTF-8 -source 8 -target 8 -nowarn -g:none -cp "$CP" \
      -d "$WORK/classes" @"$WORK/sources.txt" ;;
esac

echo "=== 3/5 merge official classes + overlay (overlay wins) ==="
for p in $MODULE_PATHS; do
  ( cd "$WORK/merge" && unzip -o -q "$p" \
      -x 'META-INF/*' 'net/java/openjdk/cacio/*' )
done
# overlay classes (org/** only) copied last so they override official
( cd "$WORK/classes" && find org -name '*.class' 2>/dev/null | while IFS= read -r f; do
    mkdir -p "$WORK/merge/$(dirname "$f")"
    cp "$f" "$WORK/merge/$f"
  done )
rm -rf "$WORK/merge/META-INF" "$WORK/merge/net" "$WORK/merge/android" "$WORK/merge/module-info.class"

echo "=== 4/5 deterministic pack ==="
if [ -z "$MANIFEST" ]; then
  MANIFEST="$WORK/MANIFEST.MF"
  # Reuse the official core manifest (keeps Specification-Version etc.)
  unzip -p "$CORE_JAR" META-INF/MANIFEST.MF > "$MANIFEST" 2>/dev/null || \
    printf 'Manifest-Version: 1.0\n\n' > "$MANIFEST"
fi
# 不自洽防御（2026-09-16 实测事故）：上游 LWJGL 的 MANIFEST 声明 `Multi-Release: true`，
# 但本脚本随后会**剥掉 META-INF/**（除 MANIFEST）**，于是「声称多版本 jar、却没有
# META-INF/versions/」→ bootstraplauncher 1.1.2（NeoForge 1.20.2 用）在 SecureJar.from 里
# Files.walk 该目录会抛 UnionFileSystem$NoSuchFileException（启动即崩）；2.0.2 有防护所以 1.21.1 无症状。
# 故这里统一去掉该属性（我们的 jar 里确实没有版本化条目）。
grep -v -i '^Multi-Release:' "$MANIFEST" > "$MANIFEST.fixed" && mv "$MANIFEST.fixed" "$MANIFEST"

python3 "$PACK_JAR" "$WORK/merge" "$MANIFEST" "$OUT/lwjgl.jar"

echo "=== 5/5 sanity ==="
python3 - "$OUT/lwjgl.jar" "$WITH_SDL" <<'PY'
import sys, zipfile
z=zipfile.ZipFile(sys.argv[1]); names=z.namelist()
with_sdl=(len(sys.argv)>2 and sys.argv[2]=="1")
cls=[n for n in names if n.endswith(".class")]
must=["org/lwjgl/glfw/GLFW.class","org/lwjgl/glfw/CallbackBridge.class",
      "org/lwjgl/glfw/GLFWWindowProperties.class","org/lwjgl/opengl/GLCapabilities.class",
      "org/lwjgl/opengl/RendererInit.class","org/lwjgl/util/freetype/FreeType.class",
      "org/lwjgl/openal/AL.class","org/lwjgl/stb/STBImage.class","org/lwjgl/vulkan/VK10.class"]
if with_sdl:
    must += ["org/lwjgl/sdl/SDL.class",
             "org/lwjgl/util/shaderc/ShadercIncludeResultReleaseI.class",
             "org/lwjgl/util/vma/Vma.class","org/lwjgl/util/spvc/Spvc.class"]
miss=[m for m in must if m not in names]
print("  classes:",len(cls),"(lwjglx:","yes" if "org/lwjgl/Sys.class" in names else "no",")")
print("  must-have missing:",miss or "none")
print("  no android/util:", not any(n.startswith("android/") for n in names))
bad=[n for n in names if n.startswith("META-INF/") and n!="META-INF/MANIFEST.MF"]
print("  stripped META-INF (except MANIFEST):", not bad)
assert not miss, "missing required classes: %s"%miss
assert len(cls)>=4000, "class count too low: %d"%len(cls)
glfw=z.read("org/lwjgl/glfw/GLFW.class")
assert b"meowcraftbridge" in glfw, \
    "GLFW overlay missing: no meowcraftbridge libname token (stock GLFW merged?)"
print("  GLFW libname token: meowcraftbridge")
PY

echo "OK -> $OUT/lwjgl.jar ($(wc -c < "$OUT/lwjgl.jar") bytes)  [LWJGL $VERSION]"
sha256sum "$OUT/lwjgl.jar"
echo "== next: python3 tools/lwjgl/pack_extras.py …  (assemble lwjgl-$VERSION.jar into the bundle; see README §3)"
