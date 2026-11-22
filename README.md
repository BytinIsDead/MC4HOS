<!--
Copyright (C) 2026 MC4HOS Contributors
SPDX-License-Identifier: MPL-2.0-no-copyleft-exception

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
-->

# MC4HOS — Minecraft: Java Edition launcher for HarmonyOS

A native, clean-room launcher that runs **Minecraft: Java Edition**
(vanilla protocol, 1.12.2 → modern releases) on **HarmonyOS 6.1.1
(API 24)** devices — phones, foldables and tablets — by embedding an
OpenJDK runtime through the HarmonyOS NDK and rendering through
XComponent surfaces. Both 64-bit ABIs are supported: **arm64-v8a**
(phones/tablets) and **x86_64** (Intel 2-in-1s and the OpenHarmony
emulator); the OHOS NDK has no 32-bit x86 ABI and the JVM needs 64-bit
anyway. aarch64 runtimes use pinned public OHOS OpenJDK builds; the
x86_64 runtime is cross-compiled by the separate tree in
[`openharmony-jdk/`](openharmony-jdk/README.md) and its GitHub Actions
workflow. The build scripts fetch the runtime packs and bundle them inside
the HAP, so phones/tablets can launch offline after install; the app falls
back to downloading a pack when the required major/ABI is not bundled.

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
│  game_surface.cpp     OH_NativeXComponent lifecycle + EGL/GLES3 self-test     │
│  log_capture.cpp      stdout/stderr pipe → latest.log + ArkTS console         │
└───────────────────────────────────┬───────────────────────────────────────────┘
                                    │ JNI (in-process)
┌───────────────────────────────────▼───────────────────────────────────────────┐
│  Embedded OpenHarmony OpenJDK (aarch64 / x86_64) — aarch64 packs ship         │
│  inside the HAP, x86_64 packs are built in openharmony-jdk/ (NATIVES.md)      │
│  + mc4hos-bridge.jar (org.mc4hos.bridge.*) + OpenHarmony-built LWJGL/OpenAL   │
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
| aarch64 OpenHarmony OpenJDK 8/17/21/25 runtimes | ✅ bundled into the HAP (fetched at build time, SHA-256 pinned) |
| x86_64 OpenHarmony OpenJDK 21/25 runtime build | ✅ separate `openharmony-jdk/` tree + CI workflow; bundled once published, otherwise downloaded/imported |
| LWJGL / OpenAL / GLFW-shim binaries | 🔶 pipeline documented in [docs/NATIVES.md](docs/NATIVES.md); build them from upstream sources |
| Desktop-GL translation (gl4es-class) | 🔶 optional component, MIT-licensed upstream |

The seams are deliberate compliance boundaries: binaries of
GPLv2+CE / BSD / LGPL projects are never committed here, only built from
pristine sources.

## Repository layout

```
AppScope/                    app-level config (bundleName, icon, label)
openharmony-jdk/             separate x86_64 OpenJDK cross-build tree (21/25)
.github/workflows/ci.yml     unsigned HAP build
.github/workflows/jdk-x86_64.yml  x86_64 runtime build/release
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
    CMakeLists.txt           builds libmc4hos_core.so (arm64-v8a + x86_64)
    napi_init.cpp            NAPI module + XComponent attach
    include/ src/            jvm_loader · jni_bridge · input_bridge ·
                             game_surface · log_capture
    java/org/mc4hos/bridge/  clean-room Java bridge (→ mc4hos-bridge.jar)
    types/mc4hos_core/       index.d.ts NAPI surface
```

## Quick start

```bash
# local build: fetches the bundled runtimes (~390 MB aarch64) then builds
scripts\build_hap.bat            # Windows (set BUNDLE_JRES=0 to skip)
scripts/build_hap.sh             # macOS/Linux
hdc install entry/build/default/outputs/default/entry-default-signed.hap
hdc shell aa start -a EntryAbility -b org.mc4hos.launcher
```

Building from the DevEco Studio GUI skips the fetch step; run
`python3 scripts/fetch_bundled_jres.py` once beforehand to bundle runtimes.
The app extracts the pack matching the device ABI and required Java major on
first use, and falls back to downloading when nothing suitable is bundled.
Full walkthrough incl. self-test mode, account setup, runtime deployment:
[docs/BUILD.md](docs/BUILD.md).

## Development & CI

- **CI builds the HAP on GitHub with zero configuration** — no secrets, no
  repository variables. `.github/workflows/ci.yml` fetches the HarmonyOS
  toolchain (commandline-tools 6.1.1.280, bundled SDK = API 24) from a
  public, login-free community mirror pinned to an immutable revision, fetches
  the bundled runtime packs, runs `ohpm install` + `hvigorw assembleHap`, and
  uploads the unsigned HAP as an artifact. Details: docs/BUILD.md §10.
- **x86_64 Java runtime** is built by `.github/workflows/jdk-x86_64.yml`
  from the separate `openharmony-jdk/` tree. Manual dispatch with
  `publish = true` publishes `jre21/25-ohos-x86_64.zip` plus a checksummed
  catalog to the `jdk-x86_64-v1` release; without publishing, the zips are
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
reconstructed. The runtime catalog covers aarch64 Java 8/17/21/25 and
x86_64 Java 21/25 — Minecraft 26.x requires Java 25, and the launcher never
falls back to an older major version. aarch64 packs are bundled in the HAP
(from `scripts/bundled-jres.lock.json`); x86_64 packs are bundled once the
`jdk-x86_64-v1` release exists and downloaded otherwise. x86_64 checksums
are refreshed from the release catalog before download; JDK8-style
`jre/lib/<arch>/server` layouts are normalized alongside modern `lib/server`.

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
