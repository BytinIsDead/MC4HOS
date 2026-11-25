<!--
Copyright (C) 2026 MC4HOS Contributors
SPDX-License-Identifier: MPL-2.0-no-copyleft-exception

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
-->

# MC4HOS — Minecraft: Java Edition launcher for HarmonyOS

A native launcher for **Minecraft: Java Edition** on **HarmonyOS 6.1.1
(API 24)** devices — phones, foldables and tablets — embedding OpenJDK
through the HarmonyOS NDK and rendering through XComponent surfaces. Both
64-bit ABIs are supported: **arm64-v8a** (phones/tablets) and **x86_64**
(Intel 2-in-1s and the OpenHarmony emulator); the OHOS NDK has no 32-bit
x86 ABI and the JVM needs 64-bit anyway. This build packages OpenJDK 21
natives and targets LWJGL3 releases requiring Java 21 or older. Releases
requiring newer Java, including current Minecraft 26.x releases, are
rejected before downloads; LWJGL2 releases are also unsupported. The build
scripts fetch the pinned Java 21 runtime packs and bundle them inside the
HAP for offline first use.

**License: MPL-2.0** (see [LICENSE](LICENSE)). Every source file carries the
standard Exhibit-A notice. This project contains no third-party proprietary
code, no game assets, and no PojavLauncher-derived code; it is written from
public protocol documentation only. See [NOTICE.md](NOTICE.md) for
trademark and third-party component obligations.

## Architecture

```
┌────────────────────────── ArkTS (UI + orchestration) ─────────────────────────┐
│  pages/  Index · Home · Versions · Console · Accounts · Settings · Licenses   │
│  auth/   MicrosoftAuth (RFC 8628 device flow → XBL/XSTS → MC services)        │
│          AccountStore (secrets in Asset Store Kit, profile in Preferences)    │
│  download/ VersionManifest · DownloadManager (taskpool ×N, SHA-1) · Installer │
│            JavaRuntimeManager (zip runtime packs)                             │
│  launch/  JvmArgumentBuilder · GameLauncher                                   │
└───────────────────────────────────┬───────────────────────────────────────────┘
                                    │ NAPI (mc4hos_core.so)
┌───────────────────────────────────▼───────────────────────────────────────────┐
│  napi_init.cpp        module registration + XComponent callbacks + API        │
│  jvm_loader.cpp       dlopen(libjvm.so) → JNI_CreateJavaVM → main(String[])   │
│  jni_bridge.cpp       JNI helpers, exception reporting, System.exit           │
│  input_bridge.cpp     overlay events → org.mc4hos.bridge.InputBridge          │
│  game_surface.cpp     OH_NativeXComponent lifecycle + direct GLFW window      │
│  log_capture.cpp      stdout/stderr pipe → latest.log + ArkTS console         │
└───────────────────────────────────┬───────────────────────────────────────────┘
                                    │ dlopen + JNI (in-process)
┌───────────────────────────────────▼───────────────────────────────────────────┐
│  Embedded OpenHarmony OpenJDK 21 (aarch64 / x86_64) + mc4hos-bridge.jar        │
│  + adapted LWJGL 3.4.3 + libmeowcraftbridge.so + OpenAL Soft + FreeType        │
└───────────────────────────────────────────────────────────────────────────────┘
```

## What is implemented vs. what is a seam

| Module | Status |
|---|---|
| Version manifest fetch/cache, per-version JSON model, rule engine | ✅ implemented |
| Threaded downloads (taskpool, streaming, SHA-1, retries, idempotent) | ✅ implemented |
| Client jar + library + asset-index + asset objects installer | ✅ implemented |
| JVM argument builder (modern `arguments.*` + legacy `minecraftArguments`) | ✅ implemented |
| Microsoft device-code OAuth → XBL/XSTS → Minecraft token chain | ✅ implemented |
| Token storage in Asset Store Kit, auto-refresh | ✅ implemented |
| Virtual mouse/dpad/buttons overlay + drag-edit layout editor | ✅ implemented |
| NAPI bridge, JVM loader, JNI main-class invocation, log capture | ✅ implemented |
| XComponent surface lifecycle + EGL/GLES3 self-test renderer | ✅ implemented |
| Dual-ABI build (arm64-v8a + x86_64), per-ABI runtime packs & natives | ✅ implemented |
| Android-style JDK/JRE import from a `.zip` (system file picker, ABI + version validation) | ✅ implemented |
| OpenHarmony OpenJDK 21 runtimes | ✅ selected for both ABIs; fetched and packaged by the build, SHA-256 pinned |
| Other OpenJDK majors | ❌ not loadable in this HAP; catalog entries alone do not provide native libraries |
| Adapted LWJGL 3.4.3 / OpenAL Soft / FreeType | ✅ reproducible builders and dual-ABI packaging; generated binaries are gitignored |
| libmeowcraftbridge.so | ✅ MC4HOS XComponent window publication, GLFW/EGL semantics and input forwarding |
| Desktop-GL translation (gl4es-class) | ❌ not included; the current game path uses system `libGLv4.so` with a core profile |

Third-party runtime and game-native binaries are built from pinned sources
and packaged at build time rather than committed. Their licenses and
corresponding-source obligations are recorded in [NOTICE.md](NOTICE.md).

## Repository layout

```
AppScope/                    app-level config (bundleName, icon, label)
openharmony-jdk/             reference copy of the dual-ABI build tree (canonical:
                             github.com/BytinIsDead/openharmony-openjdk)
.github/workflows/ci.yml     unsigned HAP build
docs/BUILD.md                step-by-step build + integration (API 24)
docs/NATIVES.md              runtime/native production pipeline
scripts/bundled-jres.lock.json  runtime packs fetched and bundled into the HAP
scripts/fetch_bundled_jres.py   build-time fetching + SHA-256 verification
entry/src/main/
  module.json5               permissions, ability, device types
  resources/rawfile/jvm/     generated runtime zips (gitignored, bundled by hvigor)
  ets/
    entryability/            EntryAbility (wiring, stores, native pump)
    pages/                   Index shell + HomeTab/Versions/Console/Accounts/
                             Settings/Licenses/GamePage/ControlsEditorPage
    auth/                    MicrosoftAuth · AccountStore · AuthModels
    download/                VersionManifest · DownloadManager · DownloadTask
                             (taskpool worker) · GameInstaller · JavaRuntimeManager
    launch/                  JvmArgumentBuilder · LaunchConfig · GameLauncher
    ui/                      ControlLayout · VirtualControls
    common/                  Http · JsonReader · Logger · Paths · AppState
  cpp/
    CMakeLists.txt           builds libmc4hos_core.so + libmeowcraftbridge.so
                             (arm64-v8a + x86_64)
    napi_init.cpp            NAPI module + XComponent attach
    include/ src/            jvm_loader · jni_bridge · input_bridge ·
                             game_surface · log_capture
    java/org/mc4hos/bridge/  clean-room Java bridge (→ mc4hos-bridge.jar)
    types/mc4hos_core/       index.d.ts NAPI surface
```

## Quick start

```bash
# local build: fetches pinned runtime packs, packages Java 21 natives, then builds
scripts\build_hap.bat            # Windows (set BUNDLE_JRES=0 to skip)
scripts/build_hap.sh             # macOS/Linux
hdc install entry/build/default/outputs/default/entry-default-signed.hap
hdc shell aa start -a EntryAbility -b org.mc4hos.launcher
```

Building from the DevEco Studio GUI skips the fetch step; run
`python3 scripts/fetch_bundled_jres.py` once beforehand to bundle runtimes.
The app extracts the Java 21 pack matching the device ABI on first use, and
falls back to downloading that pack when it is not bundled.
Full walkthrough incl. self-test mode, account setup, runtime deployment:
[docs/BUILD.md](docs/BUILD.md).

## Development & CI

- **CI builds the HAP on GitHub with zero configuration** — no secrets, no
  repository variables. `.github/workflows/ci.yml` fetches the HarmonyOS
  toolchain (commandline-tools 6.1.1.280, bundled SDK = API 24) from a
  public, login-free community mirror pinned to an immutable revision, fetches
  the bundled runtime packs, runs `ohpm install` + `hvigorw assembleHap`, and
  uploads the unsigned HAP as an artifact. Details: docs/BUILD.md §10.
- **x86_64 Java runtime** is built by the separate
  [`openharmony-openjdk`](https://github.com/BytinIsDead/openharmony-openjdk)
  repository (`jdk-ohos.yml`, which also builds aarch64 packs). Manual
  dispatch with `publish = true` publishes the zips plus a checksummed
  catalog to its `jdk-ohos-v1` release; without publishing, the zips are
  ordinary workflow artifacts for `hdc` import. Build inputs are pinned by
  SHA-256 and are never committed (GPLv2+CE).
- **Local builds** (optional convenience): `scripts\build_hap.bat`
  (Windows) / `scripts/build_hap.sh` (macOS/Linux) drive the locally
  installed DevEco Studio the same way. Both fetch the runtime packs first
  (`scripts/bundled-jres.lock.json`); set `BUNDLE_JRES=0` to build a small
  HAP that downloads runtimes instead.
- **Local sanity checks** (same as the CI `verify` job):
  ```bash
  python3 scripts/check_mpl_headers.py   # SPDX coverage
  python3 scripts/check_configs.py       # strict JSON, modelVersion, SDK strings
  ```
- **Contributing**: see CONTRIBUTING.md — includes the file-format rules
  table that keeps hvigor happy.

## HarmonyOS 6.1.1 (API 24) specifics

The project targets SDK **6.1.1.125 / API 24** (Release) and DevEco Studio
6.1.1. Areas where API 24 is used directly:

- **taskpool.Configs** — downloads run with an explicit priority and a hard
  per-file timeout (`taskpool.execute(task, { priority, timeout })`), plus
  bounded retries for 5xx/transport failures and stalled streams.
- **hidebug.getRssInfo()** and **util.ArkTSVM.getAllVMHeapMemoryInfo()** —
  Settings → Diagnostics shows process RSS/swap and ArkTS heap usage.
- **util.ArkTSVM.onVMHeapMemoryPressure()** — heap pressure is logged to the
  Console tab before an OOM kill.
- **storageStatistics** — free bytes (sync) and free inodes (API 24) are
  checked before large asset batches and shown in Diagnostics.
- **DevEco Studio 6.1.1 Hot Reload** covers native C++ sources and
  resources as well as ArkTS, so bridge iterations no longer require a full
  rebuild.

Modern Mojang metadata is handled as shipped: `${classpath}` and
`${natives_directory}` are substituted from the install tree, the native
loader owns `-cp`/`-Djava.library.path`, and the version's full
`assetIndex.url` is fetched (and SHA-1 verified) instead of being
reconstructed. The runtime catalog retains historical pack references, but this HAP packages
and loads only Java 21 native libraries. Minecraft releases requiring Java 25
or newer are rejected before authentication and downloads; the launcher never
falls back to an older major. Selected packs are pinned by size and SHA-256 in
`scripts/bundled-jres.lock.json`; missing Java 21 packs are downloaded on
demand. JDK8-style `jre/lib/<arch>/server` layouts are normalized alongside
modern `lib/server`.

Known architectural limitation: the embedded HotSpot JVM is linked
in-process, so `System.exit` ends the app process; "Leave game" closes the
application rather than returning to the dashboard. A restartable JVM
requires running the game in a separate process/service.

## Legal summary

- **This launcher:** MPL-2.0 **with Exhibit B appended** — SPDX expression
  `MPL-2.0-no-copyleft-exception` (Covered Files stay MPL-2.0; downstream
  Works may not combine them with Secondary-License code). Contributions you
  make to Covered Files are MPL-2.0 too; see Exhibit A of the license.
- **You need a Minecraft account** with a purchased license; the launcher
  authenticates against official Microsoft/Mojang endpoints and downloads
  game files from official servers at your direction. Nothing is cracked
  or bundled.
- **Bundled OpenJDK runtimes:** the HAP may redistribute OpenJDK builds
  (GPLv2 + Classpath Exception). The build writes the full GPLv2+CE text and
  a per-pack source notice to `resources/rawfile/jvm/`; the launcher copies
  them into each extracted runtime. See [NOTICE.md](NOTICE.md) for the
  corresponding-source offer. Bundling does not affect the MPL-2.0 licensing
  of the launcher's own code.
- *Minecraft* is a trademark of Mojang Synergies AB; this project is not
  affiliated with Mojang, Microsoft, or OpenHarmony/Huawei.
- The Minecraft EULA applies to your use of the game.
