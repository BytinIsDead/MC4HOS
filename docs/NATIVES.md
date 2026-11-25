<!--
Copyright (C) 2026 MC4HOS Contributors
SPDX-License-Identifier: MPL-2.0-no-copyleft-exception

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
-->

# Producing OpenHarmony Runtime & Native Components

MC4HOS includes source for its launcher, GLFW bridge and reproducible native
builders. The **Java runtime and FreeType** come from pinned OpenHarmony runtime
packs; LWJGL and OpenAL Soft are built from pinned upstream sources for the
OpenHarmony targets. All are packaged at build time and generated binaries are
not committed. This document describes the pipeline and the exact layout the
launcher expects.

> Toolchain base: the OpenHarmony NDK clang (`$OHOS_NDK/native/llvm/bin/`)
> with sysroot `$OHOS_NDK/sysroot`, for **both** 64-bit targets:
> `aarch64-linux-ohos` (phones/tablets) and `x86_64-linux-ohos` (Intel
> 2-in-1s, emulator). Musl is the libc; keep `-D__MUSL__`-style portability
> patches minimal and upstreamable. The NDK exposes no 32-bit x86 ABI, and
> the embedded JVM requires 64-bit regardless — `x86` in practice means
> `x86_64`.

## 1. Embedded OpenJDK (libjvm.so + JRE image)

This HAP packages the dlopen-able native libraries for **OpenJDK 21** on both
`aarch64-linux-ohos` and `x86_64-linux-ohos`. HarmonyOS's native-library policy
allows one OpenJDK major in the flat `entry/libs/<abi>/` namespace, and
`JavaRuntimeManager` uses Java 21 for every game requiring Java 21 or older.
Minecraft releases requiring Java 25, including current 26.x releases, are
rejected before account validation or downloads. LWJGL2 releases are rejected
by launch preflight.

### aarch64 (prebuilt, pinned, bundled)

The built-in catalog in
`entry/src/main/ets/download/JavaRuntimeManager.ets` retains historical
OpenHarmony pack references, but this build selects and extracts only the
Java 21 pack because only that major has packaged natives. Every selected
entry pins the archive size and SHA-256; downloads are rejected on any
mismatch.

At build time `scripts/fetch_bundled_jres.py` downloads the pinned archives
into `entry/src/main/resources/rawfile/jvm/` (gitignored), and
`scripts/bundle_jre_natives.py` extracts the Java 21 native libraries into
`entry/libs/<abi>/`. The lock file is `scripts/bundled-jres.lock.json`;
`BUNDLE_JRES=0` skips runtime fetching and expects the Java 21 natives to
already exist in `entry/libs/`. Pack archives and generated natives are never
committed (GitHub file limits and GPLv2+CE source-offer hygiene).

### x86_64 (built in this repository's CI)

A separate public repository,
[`BytinIsDead/openharmony-openjdk`](https://github.com/BytinIsDead/openharmony-openjdk),
cross-compiles the same pinned upstream JDK sources and OHOS patch series for
`x86_64-linux-ohos` and `aarch64-linux-ohos`. Its `jdk-ohos.yml` workflow
builds Java 21/25 for both ABIs, uploads artifacts, and — when run with
`publish = true` — publishes the packs plus `runtime-catalog.json` to the
`jdk-ohos-v1` release. MC4HOS selects the Java 21 pack for this build. The
launcher carries its SHA-256 in `scripts/bundled-jres.lock.json` and verifies
the download again at install time.

Key configure details (both ABIs, OpenJDK 21/25 build scheme; MC4HOS selects 21):

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

HarmonyOS only permits `dlopen` from the installed HAP native-library
directory. The launcher puts `applicationInfo.nativeLibraryPath` first in
`java.library.path`; sandbox-extracted Minecraft natives are not loadable.
The required flat files are packaged under `entry/libs/<abi>/`:

| Library | Source | Notes |
|---|---|---|
| `libmeowcraftbridge.so` | `entry/src/main/cpp/meowcraftbridge` + MC4HOS integration | GLFW semantics, EGL surface/context, input pumping |
| `liblwjgl_343.so` | LWJGL 3.4.3 | generation-tagged core bindings |
| `liblwjgl_343_opengl.so` | LWJGL 3.4.3 | desktop OpenGL bindings |
| `liblwjgl_343_stb.so` | LWJGL 3.4.3 | image/font helpers |
| `liblwjgl_tinyfd.so` | LWJGL 3.4.3 | file dialogs |
| `libopenal.so` | OpenAL Soft 1.24.3 with OHAudio backend | spatial audio |
| `libfreetype.so` | FreeType | font rasterization used by LWJGL |

`libmc4hos_core.so` publishes MC4HOS's existing `OHNativeWindow*` directly
to `libmeowcraftbridge.so`; it does not create a second JVM or a second
surface. The adapted LWJGL fat JAR routes GLFW to that bridge. Stock
`org.lwjgl` artifacts are excluded from the Minecraft classpath so only the
adapted provider is present.

### 2.1 Reproducible builders

Build both 64-bit ABIs and stage the generated files directly into the entry
module:

```bash
sh scripts/native/build_stack.sh \
  --sdk-native "$DEVECO_SDK_HOME/default/openharmony/native" \
  --api 24
python3 scripts/bundle_jre_natives.py
python3 scripts/check_native_stack.py
```

The wrapper fetches LWJGL 3.4.3 at commit
`30fac9b95f99cda97312232be25ba55297bf9951`, libffi 3.8.0 at commit
`12ffd1f9dc56fcea79d2f742f424301ae668d663`, and the checksum-pinned OpenAL Soft
1.24.3 archive. It builds the adapted fat JAR plus LWJGL core/OpenGL/STB/tinyfd
and OpenAL for `arm64-v8a` and `x86_64`. Pass `--abi x86_64` (repeatable) to
build only selected ABIs, `--work DIR` to relocate the source/build cache, and
`--ninja FILE` when Ninja is not on `PATH`.

Sources and intermediates stay under `.build/native-stack/` by default.
Generated libraries are staged under `entry/libs/<abi>/`, and the adapted JAR
under `entry/src/main/resources/rawfile/bridge/lwjgl-3.4.3.jar`; those output
locations are gitignored. `build_hap.bat`, `build_hap.sh`, and CI run
`check_native_stack.py` so a fresh checkout fails clearly instead of producing
a HAP without the game runtime. The corresponding source pins, licenses and
relinking instructions are recorded in [NOTICE.md](../NOTICE.md) and
`scripts/licenses/`.

### 2.2 Graphics pipeline

The game launch path preloads system `libGLv4.so` with global visibility,
selects `MEOWCRAFT_RENDERER=openglv4`, requests a core profile and disables
Gallium threaded context by default (`GALLIUM_THREAD=0`). LWJGL capability
guards remain enabled. The bridge's upstream GLES2 fallback is not sufficient
for modern Minecraft, and no gl4es core backend is included in this build.
Vulkan is not part of the current game launch path.

## 3. mc4hos-bridge.jar

Compile the clean-room Java bridge in `entry/src/main/cpp/java/`:

```bash
python3 scripts/build_bridge_jar.py
```

The generated `mc4hos-bridge.jar` is staged under
`entry/src/main/resources/rawfile/bridge/`; do not copy it into the sandbox.

`JvmArgumentBuilder` prepends both `bridge/mc4hos-bridge.jar` and the adapted
`bridge/lwjgl-3.4.3.jar` to the game classpath. `DeployImport` stages both
from HAP rawfiles atomically and refreshes them when their version marker
changes; launch fails if either cannot be staged.

## 4. Sanity matrix

| Artifact | Path in sandbox | Consumed by |
|---|---|---|
| bundled pack (in HAP) | `resources/rawfile/jvm/jre<major>-ohos-<abi>.zip` | `JavaRuntimeManager.installBundled()` (extracted on first use) |
| libjvm.so | HAP `libs/<abi>/` (the extracted runtime keeps its standard image layout) | `jvm_loader.cpp` (dlopen) |
| runtime.json | `jvm/<name>/runtime.json` (homePath = normalized JRE root) | `JavaRuntimeManager.listInstalled()` |
| mc4hos-bridge.jar | `bridge/mc4hos-bridge.jar` (ABI-independent bytecode) | classpath head |
| libmc4hos_core.so + libmeowcraftbridge.so | HAP `libs/<abi>/` | NAPI module and GLFW bridge |
| liblwjgl*.so / libopenal.so / libfreetype.so | HAP `libs/<abi>/` | `java.library.path` |
| lwjgl-3.4.3.jar | `bridge/lwjgl-3.4.3.jar` (staged from HAP) | adapted GLFW provider on classpath |
| latest.log | `logs/latest.log` | Console tab + `hdc hilog` |

Everything the game needs at runtime (client jar, libraries, assets) is
downloaded by the launcher itself from official Mojang endpoints — nothing
game-related is built or stored in this repository. A version is installed
only after its client, required libraries and asset objects succeed and the
`.installed` marker is written.
