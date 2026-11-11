<!--
Copyright (C) 2026 MC4HOS Contributors
SPDX-License-Identifier: MPL-2.0

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

Targets: **OpenJDK 8, 17 and 21** images for both `aarch64-linux-ohos` and
`x86_64-linux-ohos`.

1. Start from upstream OpenJDK sources (no forks required for the JRE image
   itself).
2. Configure cross-build with the OHOS clang and sysroot, once per target:
   `--openjdk-target=aarch64-linux-ohos --with-sysroot=$OHOS_NDK/sysroot`
   and `--openjdk-target=x86_64-linux-ohos …` respectively, plus the usual
   `--with-jvm-variants=server`. The x86_64 pass typically needs no source
   patches at all beyond the musl notes below.
3. Port notes (kept minimal, upstreamable):
   - `os_linux.cpp`/`os_posix` family: OpenHarmony is Linux-kernel
     compatible for what the JVM touches (mmap, pthreads, epoll); the main
     deltas are musl stack-guard behavior and `dlvsym` absence — identical
     for both targets.
   - JVM_dynamic/foreign: not needed for Minecraft workloads.
4. Result layout consumed by `JavaRuntimeManager` (per ABI — the manager
   picks the pack whose name/ABI matches `Paths.deviceAbi()`):

```
jvm/jre17-ohos-x86_64/
├── bin/                 # java, keytool (optional)
├── lib/
│   ├── rt modules (modules image or exploded classes)
│   └── server/libjvm.so # ← dlopen()ed by libmc4hos_core.so
├── release
└── runtime.json         # {"name":"jre17-ohos-x86_64","javaMajor":17,"abi":"x86_64","homePath":"<abs>"}
```

Zip the whole directory (archive root = `bin/…`/`lib/…`) as a **runtime
pack** and point `RUNTIME_CATALOG` in
`ets/download/JavaRuntimeManager.ets` at its URL; the manager downloads,
extracts and stamps `runtime.json` automatically.

## 2. Game native stack (`java.library.path`)

Minecraft loads natives by name (`System.loadLibrary("lwjgl")`,
`"openal"`). The launcher passes
`<files>/mc4hos/natives/<mcVersion>/<abi>:<javaHome>/lib/server:…` as
`-Djava.library.path`, where `<abi>` is `arm64-v8a` or `x86_64` (resolved
from `Paths.deviceAbi()`). Build and deploy per ABI:

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
  entry/src/main/cpp/java/org/mc4hos/bridge/PlatformBridge.java
jar cf mc4hos-bridge.jar -C build .
hdc file send mc4hos-bridge.jar <sandbox>/bridge/
```

`JvmArgumentBuilder` prepends `bridge/mc4hos-bridge.jar` to the classpath
automatically when the file exists.

## 4. Sanity matrix

| Artifact | Path in sandbox | Consumed by |
|---|---|---|
| libjvm.so | `jvm/<name>/lib/server/libjvm.so` (name encodes ABI) | `jvm_loader.cpp` (dlopen) |
| runtime.json | `jvm/<name>/runtime.json` | `JavaRuntimeManager.listInstalled()` |
| mc4hos-bridge.jar | `bridge/mc4hos-bridge.jar` (ABI-independent bytecode) | classpath head |
| liblwjgl*.so / libopenal.so | `natives/<mcVersion>/<abi>/` | `java.library.path` |
| latest.log | `logs/latest.log` | Console tab + `hdc hilog` |

Everything the game needs at runtime (client jar, libraries, assets) is
downloaded by the launcher itself from official Mojang endpoints — nothing
game-related is built or stored in this repository.
