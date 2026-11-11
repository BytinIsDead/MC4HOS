<!--
Copyright (C) 2026 MC4HOS Contributors
SPDX-License-Identifier: MPL-2.0

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
-->

# MC4HOS — Minecraft: Java Edition launcher for HarmonyOS

A native, clean-room launcher that runs **Minecraft: Java Edition**
(vanilla protocol, 1.12.2 → modern releases) on **HarmonyOS 6.1.1
(API 24)** devices — phones, foldables and tablets — by embedding an
ARM64 OpenJDK runtime through the HarmonyOS NDK and rendering through
XComponent surfaces. Both 64-bit ABIs are supported: **arm64-v8a**
(phones/tablets) and **x86_64** (Intel 2-in-1s and the OpenHarmony
emulator); the OHOS NDK has no 32-bit x86 ABI and the JVM needs 64-bit
anyway.

**License: MPL-2.0** (see [LICENSE](LICENSE)). Every source file carries the
standard Exhibit-A notice. This project contains no third-party proprietary
code, no game assets, and no PojavLauncher-derived code; it is written from
public protocol documentation only. See [NOTICE.md](NOTICE.md) for
trademark and third-party component obligations.

## Architecture

```
┌────────────────────────── ArkTS (UI + orchestration) ─────────────────────────┐
│  pages/  Index · HomeTab · Versions · Console · Accounts · Settings · Editor  │
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
│  Embedded OpenHarmony OpenJDK (aarch64) — built separately (docs/NATIVES.md)  │
│  + mc4hos-bridge.jar (org.mc4hos.bridge.*) + OpenHarmony-built LWJGL/OpenAL   │
└───────────────────────────────────────────────────────────────────────────────┘
```

## What is implemented vs. what is a seam

| Module | Status |
|---|---|
| Version manifest fetch/cache, per-version JSON model, rule engine | ✅ implemented |
| Threaded downloads (taskpool pool, streaming, SHA-1, idempotent) | ✅ implemented |
| Client jar + library + asset-index + asset objects installer | ✅ implemented |
| JVM argument builder (modern `arguments.*` + legacy `minecraftArguments`) | ✅ implemented |
| Microsoft device-code OAuth → XBL/XSTS → Minecraft token chain | ✅ implemented |
| Token storage in Asset Store Kit, auto-refresh | ✅ implemented |
| Virtual mouse/dpad/buttons overlay + drag-edit layout editor | ✅ implemented |
| NAPI bridge, JVM loader, JNI main-class invocation, log capture | ✅ implemented |
| XComponent surface lifecycle + EGL/GLES3 self-test renderer | ✅ implemented |
| Dual-ABI build (arm64-v8a + x86_64), per-ABI runtime packs & natives | ✅ implemented |
| OpenHarmony OpenJDK / LWJGL / OpenAL binaries | 🔶 pipeline documented in [docs/NATIVES.md](docs/NATIVES.md); build them from upstream sources |
| GLFW window/input shim for LWJGL | 🔶 seam defined (InputBridge + PlatformBridge contracts) |
| Desktop-GL translation (gl4es-class) | 🔶 optional component, MIT-licensed upstream |

The seams are deliberate compliance boundaries: binaries of
GPLv2+CE / BSD / LGPL projects are never committed here, only built from
pristine sources.

## Repository layout

```
AppScope/                    app-level config (bundleName, icon, label)
docs/BUILD.md                step-by-step build + integration (API 24)
docs/NATIVES.md              runtime/native production pipeline
entry/src/main/
  module.json5               permissions, ability, device types
  ets/
    entryability/            EntryAbility (wiring, stores, native pump)
    pages/                   Index shell + HomeTab/Versions/Console/Accounts/
                             Settings/GamePage/ControlsEditorPage
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
# in DevEco Studio: open repo, sign in project, Build Hap(s)
hdc install entry/build/default/outputs/default/entry-default-signed.hap
hdc shell aa start -a EntryAbility -b org.mc4hos.launcher
```

Full walkthrough incl. self-test mode, account setup, runtime deployment:
[docs/BUILD.md](docs/BUILD.md).

## Legal summary

- **This launcher:** MPL-2.0. Contributions you make to Covered Files are
  MPL-2.0 too; see Exhibit A of the license.
- **You need a Minecraft account** with a purchased license; the launcher
  authenticates against official Microsoft/Mojang endpoints and downloads
  game files from official servers at your direction. Nothing is cracked
  or bundled.
- *Minecraft* is a trademark of Mojang Synergies AB; this project is not
  affiliated with Mojang, Microsoft, or OpenHarmony/Huawei.
- The Minecraft EULA applies to your use of the game.
