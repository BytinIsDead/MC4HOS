<!--
Copyright (C) 2026 MC4HOS Contributors
SPDX-License-Identifier: MPL-2.0-no-copyleft-exception

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
-->

# Producing OpenHarmony Runtime & Native Components

MC4HOS's launcher code is complete, but the **Java runtime** and the game's
**native dependency stack** are not code this repository can ship: they are
binaries of third-party projects (OpenJDK, LWJGL, OpenAL Soft) that each
distributor builds from pristine upstream sources for the OpenHarmony
targets. This document describes the pipeline and the exact layout the
launcher expects. All builds happen **outside** this repository.

> Toolchain base: the OpenHarmony NDK clang (`$OHOS_NDK/native/llvm/bin/`)
> with sysroot `$OHOS_NDK/sysroot`, for **both** 64-bit targets:
> `aarch64-linux-ohos` (phones/tablets) and `x86_64-linux-ohos` (Intel
> 2-in-1s, emulator). Musl is the libc; keep `-D__MUSL__`-style portability
> patches minimal and upstreamable. The NDK exposes no 32-bit x86 ABI, and
> the embedded JVM requires 64-bit regardless — `x86` in practice means
> `x86_64`.

## 1. Embedded OpenJDK (libjvm.so + JRE image)

Targets: **OpenJDK 8, 17, 21 and 25** images for `aarch64-linux-ohos`; the
separate x86_64 tree builds **21 and 25** for `x86_64-linux-ohos`. Java 25 is
required by current Minecraft releases (26.x); 1.20.5–1.21.x need 21 and
1.12.2 needs 8. The launcher selects an exact or newer major, never an older
one, so Java 21 also covers 1.17–1.20.4.

### aarch64 (prebuilt, pinned, bundled)

The built-in catalog in
`entry/src/main/ets/download/JavaRuntimeManager.ets` points at public
community OpenHarmony builds of JDK 8/17/21/25. Every entry pins the archive
size and SHA-256; downloads are rejected on any mismatch.

At build time `scripts/fetch_bundled_jres.py` downloads those same pinned
archives into `entry/src/main/resources/rawfile/jvm/` (gitignored), so the
HAP carries all four aarch64 runtimes (~390 MB) and the app can extract them
offline on first use. The lock file is
`scripts/bundled-jres.lock.json`; `BUNDLE_JRES=0` skips the fetch for a
smaller HAP that downloads packs instead. The pack archives are never
committed (100 MB GitHub file limit and GPLv2+CE source-offer hygiene).

### x86_64 (built in this repository's CI)

There is no public x86_64 OHOS JRE. The separate tree in `openharmony-jdk/`
cross-compiles the same pinned upstream JDK sources and OHOS patch series for
`x86_64-linux-ohos`. `.github/workflows/jdk-x86_64.yml` builds
`jre21-ohos-x86_64.zip` and `jre25-ohos-x86_64.zip`, uploads artifacts, and —
when run with `publish = true` — publishes them plus `runtime-catalog.json`
to the `jdk-x86_64-v1` release. The launcher fetches that catalog to obtain
the per-build SHA-256 before downloading. Once the release exists, the build
scripts also fetch and bundle both packs (their lock entries are optional
until then). See `openharmony-jdk/README.md`
for the local build command and licensing requirements.

Key configure details (both ABIs, OpenJDK 21/25 scheme):

- Cross-compile with the OHOS NDK clang, but keep autoconf's target OS as
  Linux/musl: `--openjdk-target=x86_64-unknown-linux-musl` (or
  `aarch64-unknown-linux-musl`) while `CC` is the OHOS
  `x86_64-linux-ohos-clang` wrapper. Do **not** pass
  `--openjdk-target=x86_64-linux-ohos`; OpenJDK parses `ohos` as the target
  OS and the build system fails.
- Add `--with-jvm-variants=server --enable-headless-only`, the OHOS sysroot
  and libc++ paths, and the community musl/OHOS patch series (dlvsym/dlinfo,
  utmpx, IPv6 sandbox fallback, child-process and JavaSound fixes).
- The produced image must be packaged with `libc++_shared.so` and the thin
  `libcxxabi_shim.so` facade, plus upstream `LICENSE`,
  `ADDITIONAL_LICENSE_INFO`, `ASSEMBLY_EXCEPTION`, and the OHOS SDK
  `NOTICE.txt`.

### Layout consumed by the launcher

```
jvm/jre21-ohos-x86_64/          # modern layout
├── bin/
├── lib/
│   └── server/libjvm.so        # ← dlopen()ed by libmc4hos_core.so
├── release
└── runtime.json                # {"name":…,"javaMajor":21,"abi":"x86_64","homePath":"<abs JRE root>"}

jvm/jre8-ohos-aarch64/           # JDK8 layout
└── jre/
    ├── bin/
    └── lib/aarch64/server/libjvm.so
```

The manager recursively locates the JRE root (checking `lib/server`,
`lib/<arch>/server`, and nested `jre/`), stores that normalized path in
`runtime.json`, and builds `java.library.path` from the directories that
actually exist. `jvm_loader.cpp` tries the same layouts before `dlopen`.
Packs must therefore keep a standard JDK image tree; no custom relocation is
required.

Zip either image with the archive root at `bin/`/`lib/` (modern) or
`jre/` (JDK8) as a **runtime pack**. Catalog entries carry `sha256` and
`sizeBytes`; `JavaRuntimeManager` rejects ABI mismatches, size/checksum
mismatches, and packs without a discoverable `libjvm.so`. Packs can also be
imported from `/data/local/tmp` (Settings → Deployment) when a release is not
available.

## 2. Game native stack (`java.library.path`)

Minecraft loads natives by name (`System.loadLibrary("lwjgl")`,
`"openal"`). The launcher passes
`<files>/mc4hos/natives/<mcVersion>/<abi>:<javaHome>/lib/server:<javaHome>/lib:…`
as `-Djava.library.path`, where `<abi>` is `arm64-v8a` or `x86_64` (resolved
from `Paths.deviceAbi()`), and the JDK directories are selected from the
runtime's actual layout (`lib/server`, `lib/<arch>/server`, …). Build and
deploy per ABI:

| Library | Source | Notes |
|---|---|---|
| `liblwjgl.so` | LWJGL 3.3.x, `ant compile-native` adapted to OHOS clang | core bindings, both targets |
| `liblwjgl_opengl.so` | LWJGL | GL bindings |
| `liblwjgl_glfw.so` | LWJGL + **glfw-ohos shim** (§2.1) | window/input layer |
| `libopenal.so` | OpenAL-Soft, cmake toolchain=ohos | audio; x86_64 has full JIT (NEON not required) |
| `libGL.so` (optional) | gl4es (MIT) | desktop-GL → GLES translation for ≤1.12.2 pipelines |

### 2.1 The GLFW/window shim (the key seam)

LWJGL's `liblwjgl_glfw.so` normally creates platform windows itself. On
OpenHarmony the surface is owned by our XComponent, so you compile LWJGL's
GLFW module against a thin **shim library** that implements the GLFW window
surface on the existing `OHNativeWindow*` and surfaces input from
`org.mc4hos.bridge.InputBridge` (built into `mc4hos-bridge.jar`, see §4).
The shim reads its window handle from `PlatformBridge` state — native
already hands the JVM the live XComponent geometry at startup
(`onGameSurfaceCreated`). This is the same architectural seam pattern used
by every non-Android mobile Java launcher; the implementation is
straightforward GLFW surface plumbing and is *your* integration work.

### 2.2 Graphics pipeline mapping

- MC ≤ 1.16 era (LWJGL2/legacy GL): render through **gl4es** (`libGL.so`
  exposing desktop GL 1.5/2.x over the device's GLES 3.1/3.2), EGL context
  on the XComponent window.
- MC ≥ 1.17 (LWJGL3 + GL core): either run the same gl4es translation
  layer, or supply a GLES-native rendering path via the shim.
- Vulkan path: the XComponent window is a standard `OHNativeWindow`;
  `vkCreateAndroidSurfaceKHR`-equivalent OHOS extension
  (`VK_OHOS_surface`) can be used by future shim versions.

## 3. mc4hos-bridge.jar

Compile the clean-room Java bridge in `entry/src/main/cpp/java/`:

```bash
javac -source 8 -target 8 -d build \
  entry/src/main/cpp/java/org/mc4hos/bridge/InputBridge.java \
  entry/src/main/cpp/java/org/mc4hos/bridge/PlatformBridge.java \
  entry/src/main/cpp/java/org/mc4hos/bridge/SelfTest.java
jar cf mc4hos-bridge.jar -C build .
hdc file send mc4hos-bridge.jar <sandbox>/bridge/
```

`JvmArgumentBuilder` prepends `bridge/mc4hos-bridge.jar` to the classpath
automatically when the file exists.

## 4. Sanity matrix

| Artifact | Path in sandbox | Consumed by |
|---|---|---|
| bundled pack (in HAP) | `resources/rawfile/jvm/jre<major>-ohos-<abi>.zip` | `JavaRuntimeManager.installBundled()` (extracted on first use) |
| libjvm.so | `jvm/<name>/lib/server/libjvm.so` or `jvm/<name>/jre/lib/<arch>/server/libjvm.so` | `jvm_loader.cpp` (dlopen) |
| runtime.json | `jvm/<name>/runtime.json` (homePath = normalized JRE root) | `JavaRuntimeManager.listInstalled()` |
| mc4hos-bridge.jar | `bridge/mc4hos-bridge.jar` (ABI-independent bytecode) | classpath head |
| liblwjgl*.so / libopenal.so | `natives/<mcVersion>/<abi>/` | `java.library.path` |
| latest.log | `logs/latest.log` | Console tab + `hdc hilog` |

Everything the game needs at runtime (client jar, libraries, assets) is
downloaded by the launcher itself from official Mojang endpoints — nothing
game-related is built or stored in this repository.
