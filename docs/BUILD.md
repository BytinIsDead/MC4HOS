<!--
Copyright (C) 2026 MC4HOS Contributors
SPDX-License-Identifier: MPL-2.0

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
-->

# Building and Integrating MC4HOS on HarmonyOS 6.1.1 (API 24)

Everything in this repository builds with **DevEco Studio** and the
**HarmonyOS SDK**. Nothing proprietary is compiled from this tree; the
runtime components the launcher downloads/loads are built from upstream
sources by *you* (see [NATIVES.md](NATIVES.md)).

## 1. Prerequisites

| Tool | Version | Notes |
|---|---|---|
| DevEco Studio | 6.x (or 5.x with API 24 SDK) | Bundles hvigor + ArkTS compiler |
| HarmonyOS SDK | API **24** (`compatibleSdkVersion: "6.1.1(24)"`) | Enable **Native SDK** (C++ toolchain) in SDK manager |
| Device / emulator | HarmonyOS 6.1.1, **arm64-v8a or x86_64** | Real device recommended (JVM + GPU required). The OHOS NDK has no 32-bit x86 ABI; the emulator and Intel 2-in-1s run `x86_64` |
| hdc | from SDK | `hdc install`, `hdc file send`, logs via `hdc hilog` |
| (runtime) OpenJDK OHOS builds | 8 / 17 / 21 × {arm64-v8a, x86_64} | produced per [NATIVES.md](NATIVES.md) |
| (runtime) LWJGL / OpenAL-Soft OHOS builds | 3.3.x × both ABIs | produced per [NATIVES.md](NATIVES.md) |

## 2. Open and configure the project

1. `File → Open` and select this repository root (`MC4HOS/`).
2. When prompted, run **`hvigor` sync** (Tools → Hvigor → Sync).
3. Confirm the SDK: `File → Project Structure → General` shows
   *Compile SDK: 6.1.1(24)*. If your installed SDK string differs
   (e.g. `6.0.0(20)`), edit the SDK strings in `build-profile.json5` to
   match exactly.
4. Signing: `File → Project Structure → Signing Configs` → check
   **Automatically generate signature** (debug). For release, supply your
   `.p12` + `.cer` + `.p7b` material.

### Sync-critical schema rules (DevEco Studio 6.1.1)

These broke sync during bring-up; keep them intact when editing configs:

- **`modelVersion` must exist in BOTH** root `oh-package.json5` and
  `.hvigor/hvigor-config.json5`, and must equal the paired DevEco Studio
  version (`"6.1.1"` for DevEco Studio 6.1.1 Release; minimum allowed
  `"5.0.0"`). A missing or mismatched value is the most common sync
  failure.
- **HarmonyOS SDK strings require the `(api)` suffix**: with
  `runtimeOS: "HarmonyOS"`, write `"6.1.1(24)"` — a bare `"6.1.1"` does not
  resolve. Rule: `compatibleSdkVersion ≤ targetSdkVersion ≤
  compileSdkVersion`, all in `app.products[]`.
- **`app.json5` requires `buildVersion`** (6.x schema) — see AppScope.
- **JSON5 comments are `//` or `/* */` only** — `#` lines fail hvigor's
  parser at read time. Conversely, `resources/**/*.json` and
  `profile/*.json` are parsed by **strict JSON** (restool, error 11203002):
  no comments at all in those files.
- **`app.json5` icon must be a PNG** (SVG is rejected for app icons).
- **DevEco normalizes configs on sync** — it may reformat
  `build-profile.json5`, drop an explicit `compileSdkVersion` (taking it
  from the installed IDE SDK — benign) and generate its own
  `hvigor/hvigor-config.json5`. If it strips license headers during
  normalization, re-add them (see NOTICE.md).

## 3. Build the HAP

DevEco (GUI): `Build → Build Hap(s)/APP(s) → Build Hap(s)`.

Command line:

```bash
hvigorw assembleHap --mode module -p product=default -p buildMode=release
# artifact: entry/build/default/outputs/default/entry-default-signed.hap
```

The CMake native build (`entry/src/main/cpp/CMakeLists.txt`) runs once per
ABI in `abiFilters` and produces `libmc4hos_core.so` for **`arm64-v8a` and
`x86_64`**. Both variants ship in the HAP; strip `x86_64` from `abiFilters`
for a smaller release targeting only ARM phones.

## 4. Install and run

```bash
hdc install entry/build/default/outputs/default/entry-default-signed.hap
hdc shell aa start -a EntryAbility -b org.mc4hos.launcher
```

Live logs:

```bash
hdc hilog | grep -E "MC4HOS|Game"
```

## 5. First-run verification (recommended order)

1. **Self-test render** — Settings → enable *Native self-test mode* → Home →
   PLAY. You should see the animated EGL/GLES clear-surface on the
   XComponent with no account or downloads required. This proves
   XComponent → `libmc4hos_core.so` → EGLNativeWindow pipeline.
2. **Console tab** — verify native `initialize()` log pump works
   (lines tagged `Game`).
3. **Account** — configure the Azure client id (§7), sign in on the
   Accounts tab (device-code flow).
4. **Versions tab** — install a release (client jar + libraries + assets).
5. **Runtime** — install an OpenHarmony JRE pack (§6), confirm
   `jvm/jre17-ohos-<abi>/runtime.json` exists (the launcher logs the device
   ABI at startup: `device ABI: arm64-v8a` / `x86_64`).
6. **Natives** — deploy `liblwjgl.so` etc. into
   `files/mc4hos/natives/<mcVersion>/<abi>/` (§6), plus
   `bridge/mc4hos-bridge.jar`.
7. Home → PLAY.

## 6. Deploying runtimes and natives onto the device

The app sandbox directory is
`/data/app/el2/100/base/org.mc4hos.launcher/haps/entry/files/mc4hos/`.
Replace `<abi>` with the device architecture (`arm64-v8a` on phones/tablets,
`x86_64` on Intel 2-in-1s and the emulator — `hdc shell "param get
const.product.cpu.abilist"` prints it). With the app **not running**:

```bash
hdc shell mkdir -p <sandbox>/jvm/jre17-ohos-x86_64
hdc file send jre17-ohos-x86_64.zip <sandbox>/jvm/
# then extract from the device shell, or use JavaRuntimeManager.install()
# which downloads + unzips for you (zip layout per NATIVES.md)

hdc file send mc4hos-bridge.jar <sandbox>/bridge/
hdc shell mkdir -p <sandbox>/natives/1.20.4/<abi>
hdc file send liblwjgl.so <sandbox>/natives/1.20.4/<abi>/
hdc file send liblwjgl_glfw.so <sandbox>/natives/1.20.4/<abi>/
hdc file send libopenal.so <sandbox>/natives/1.20.4/<abi>/
```

The launcher selects runtime packs and natives by `Paths.deviceAbi()`, so a
sandbox may hold both architectures side by side
(`natives/1.20.4/arm64-v8a/` and `natives/1.20.4/x86_64/`).

Sandbox paths for debug builds can also be browsed via DevEco
`Device File Browser`.

## 7. Microsoft OAuth: your Azure application

MC4HOS deliberately ships **no** Microsoft client id (see NOTICE.md).
Each distributor registers one:

1. https://portal.azure.com → Microsoft Entra ID → App registrations →
   **New registration**.
2. *Supported account types*: **Personal Microsoft accounts only**
   (consumers) or the multitenant+personal option.
3. Authentication → **Allow public client flows: Yes** (required for
   device-code flow). No redirect URI and no client secret needed.
4. Copy the *Application (client) ID* and either paste it into the app's
   Settings page, or pre-seed it by adding it to
   `EntryAbility.onCreate` via `MicrosoftAuth.configure("<client-id>")`
   behind your own build flag.

The requested scope is fixed to `XboxLive.signin offline_access` in
`auth/MicrosoftAuth.ets`.

## 8. Troubleshooting

| Symptom | Likely cause |
|---|---|
| Sync fails immediately, JSON parse error | `#` comments or trailing commas in a `.json5` — use `//` only |
| Error 11203002 "Failed to parse the JSON file" at CompileResource | comments in strict-JSON resources — `resources/**/*.json` and `profile/*.json` must be comment-free JSON (unlike `.json5` configs) |
| `modelVersion` mismatch / "please upgrade hvigor" | `oh-package.json5` and `.hvigor/hvigor-config.json5` must both carry the DevEco version, e.g. `"6.1.1"` |
| "Invalid/unknown compatibleSdkVersion" | SDK string missing its `(api)` suffix (must be `"6.1.1(24)"` for HarmonyOS), or ordering rule `compatible ≤ target ≤ compile` violated |
| CMake error "variable ... set to NOTFOUND" | HMOS sysroot may lack a probed lib — probe `NAMES <name> <name>.z` and link conditionally (see CMakeLists nativewindow handling) |
| `fatal error: 'jni.h' file not found` at BuildNativeWithNinja | the OHOS NDK ships no `jni.h` — `cpp/include/jni_compat.h` provides the clean-room ABI subset; do not include `<jni.h>` anywhere |
| `dlopen(libjvm) failed` in console | JRE pack not installed under `jvm/<name>/lib/server/libjvm.so` |

### Local native verification (no device needed)

The six C++ sources can be compiled+linked without DevEco's GUI, mirroring
ninja's flags (useful to iterate on native errors fast):

```bash
SDK="C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/native"
"$SDK/llvm/bin/clang++.exe" --target=x86_64-linux-ohos \
  --sysroot="$SDK/sysroot" -D__MUSL__ -std=gnu++17 -fPIC -fexceptions -frtti \
  -I"C:/Program Files/Huawei/DevEco Studio/sdk/default/hms/native/sysroot/usr/include" \
  -Ientry/src/main/cpp/include -c entry/src/main/cpp/napi_init.cpp -o /tmp/t.o
```
| `JNI_CreateJavaVM failed (code …)` | JVM built for wrong **ABI** or libc — pack must match `Paths.deviceAbi()` (logged at startup) and be a musl/ohos build |
| Surface stays black, self-test on | EGL config mismatch — try removing alpha bits in `game_surface.cpp` |
| Overlay input ignored | game not running (events before VM start are dropped; check `[MC4HOS] input bridge` line) |
| Downloads stall | `ohos.permission.INTERNET` must be granted (module.json5 already declares it); check `hdc hilog` for HTTP codes |
| `compatibleSdkVersion` error at build | SDK string mismatch — copy the exact string from SDK manager |
| x86_64 emulator crash at JVM load | runtime pack or natives deployed from the ARM tree — both paths are ABI-qualified, see §6 |

## 9. Compliance checklist for distribution

- Keep the MPL-2.0 header in every modified/added source file (Exhibit A).
- Provide this repository's source (MPL §3.2) when distributing HAPs.
- Do **not** redistribute OpenJDK/LWJGL/OpenAL binaries without preserving
  their license texts — build them from pristine upstream sources and ship
  their NOTICE files alongside (see NOTICE.md).
- Never bundle game assets; the launcher fetches them from Mojang's
  official servers only, on behalf of an authenticated, licensed user.
