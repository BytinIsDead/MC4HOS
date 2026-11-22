<!--
Copyright (C) 2026 MC4HOS Contributors
SPDX-License-Identifier: MPL-2.0-no-copyleft-exception

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
| (runtime) OpenJDK OHOS builds | aarch64: 8 / 17 / 21 / 25; x86_64: 21 / 25 | All packs are fetched at build time and bundled in the HAP; x86_64 packs are built by [openharmony-openjdk](https://github.com/BytinIsDead/openharmony-openjdk) and published as `jdk-ohos-v1` · see [NATIVES.md](NATIVES.md); latest Minecraft releases require Java 25 |
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
python3 scripts/fetch_bundled_jres.py   # once; build scripts do this automatically
hvigorw assembleHap --mode module -p product=default -p buildMode=release
# artifact: entry/build/default/outputs/default/entry-default-signed.hap
```

The fetch step downloads the pinned packs from
`scripts/bundled-jres.lock.json` into
`entry/src/main/resources/rawfile/jvm/` (gitignored) so hvigor packages them
as stored rawfiles: roughly 390 MB of aarch64 runtimes (8/17/21/25) plus
about 120 MB of x86_64 runtimes (21/25) from `jdk-ohos-v1`. Set
`BUNDLE_JRES=0`
when using `scripts/build_hap.*` to build a small HAP without bundled
runtimes; the app then downloads packs on demand. Building from the DevEco
GUI does not run the fetch step.

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

1. **Self-test (no account, no network)** — Settings → enable
   *Native self-test mode* → Home → PLAY. If no runtime is installed yet,
   the launcher extracts a bundled pack from `resources/rawfile/jvm/` first.
   Two validations run:
   the **JVM self-test** (boots the embedded runtime, runs
   `org.mc4hos.bridge.SelfTest` from the bridge jar — watch the Console
   tab for `[MC4HOS] JVM self-test: PASS`) proves runtime pack + libjvm +
   JNI + classpath; then the animated **EGL/GLES surface self-test**
   proves XComponent → `libmc4hos_core.so` → EGLNativeWindow.
2. **Console tab** — verify native `initialize()` log pump works
   (lines tagged `Game`).
3. **Account** — sign in on the Accounts tab (device-code flow); the Azure
   client id is compiled in (§7).
4. **Versions tab** — install a release (client jar + libraries + assets).
5. **Runtime** — the launcher extracts the bundled pack that matches the
   device ABI and the version's required major on first use (aarch64 Java
   8/17/21/25; x86_64 21/25). Confirm
   `jvm/jre<major>-ohos-<abi>/runtime.json` exists (the launcher logs the
   device ABI at startup: `device ABI: arm64-v8a` / `x86_64`). Use the
   major required by the version JSON (`javaVersion.majorVersion`); current
   releases require **25**, 1.20.5–1.21.x require **21**, and 1.12.2
   requires **8**. Selection never falls back to an older major. Deploy a
   pack manually (§6) only when the needed ABI/major is not bundled.
6. **Natives** — deploy `liblwjgl.so` etc. into
   `files/mc4hos/natives/<mcVersion>/<abi>/` (§6), plus
   `bridge/mc4hos-bridge.jar`.
7. Home → PLAY.

## 6. Deploying runtimes and natives onto the device

**Bundled runtimes need no deployment.** The HAP carries
`resources/rawfile/jvm/*.zip` (fetched at build time) and extracts the
matching pack into the sandbox on first use — no network, no `hdc`.

**Manual runtime import** (when a pack is missing from the build, e.g.
`BUNDLE_JRES=0`): the in-app importer works on every device.
`hdc file send` into app sandboxes often fails with "No such file or
directory" / permission errors — but `/data/local/tmp` is world-writable:

```bash
hdc file send jre17-ohos-x86_64.zip  /data/local/tmp/
hdc file send mc4hos-bridge.jar      /data/local/tmp/
hdc file send natives-1.21.4.zip     /data/local/tmp/
```

Then in the app: Settings → **Deployment** → import each file (the app
copies them into its own sandbox, extracts runtime packs and natives, and
writes the runtime.json markers automatically).

**Importing any JDK/JRE from a `.zip`** — like Android launchers, without a
PC: Settings → **Java runtime** → **Import JDK from .zip** opens the system
document picker. Pick a `.zip` reachable by the picker (Downloads, cloud
drives, external storage). The app copies it into its sandbox, extracts it,
and validates it before registering:

- `libjvm.so` must exist at `lib/server/` (modern JDKs) or
  `lib/<arch>/server/` (JDK8 and single-folder layouts), at the archive root
  or inside one top-level folder;
- the architecture is read from `OS_ARCH` in `release`, falling back to the
  ELF header of `libjvm.so`; it must match the device ABI;
- the Java major version comes from `JAVA_VERSION` in `release`, falling
  back to the archive name (`jre21…`, `jdk-8…`).

Each import gets a unique name (`jre21-ohos-x86_64-2` when the first is
already installed) and a `runtime.json` marker, appears under *Installed
runtimes*, and is picked automatically by the required Java version. A
failed import removes the partial extraction and the copied zip. The
imported JDK keeps its own license; MC4HOS does not support or redistribute
third-party JDK builds.

The app sandbox directory is
`/data/app/el2/100/base/org.mc4hos.launcher/haps/entry/files/mc4hos/`
(emulator/rooted devices and DevEco's Device File Browser can write there
directly; on stock devices use the importer above). Replace `<abi>` with the device architecture (`arm64-v8a` on phones/tablets,
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

Packs installed by `JavaRuntimeManager.install()` must match the device ABI,
carry a pinned SHA-256 and size in the catalog, and contain a discoverable
`libjvm.so` (`lib/server/` for modern JDKs, `lib/<arch>/server/` for JDK8);
otherwise installation is rejected. Bundled packs go through the same size,
digest (when pinned) and layout checks after being copied out of the HAP.
Imported packs (Settings → Deployment)
are parsed from their `jre<major>-ohos-<abi>.zip` (or `jdk…`) name and use
the same layout discovery.

For **x86_64**, build the pack in the separate
[openharmony-openjdk](https://github.com/BytinIsDead/openharmony-openjdk)
repository (`scripts/build_ohos_jre.sh --arch x86_64`, or download the CI
artifact from the `jdk-ohos-v1` release) and import
`jre21-ohos-x86_64.zip` / `jre25-ohos-x86_64.zip` exactly as above. No
aarch64 runtime can run on x86_64 — the JVM is loaded in-process.

Sandbox paths for debug builds can also be browsed via DevEco
`Device File Browser`.

## 7. Microsoft OAuth: the Azure application

MC4HOS compiles a Microsoft OAuth **public client** id into the app
(`AZURE_CLIENT_ID` in `entry/src/main/ets/common/AppState.ets`; applied at
startup by `EntryAbility` via `MicrosoftAuth.configure`). It is **not** a
secret and device-code flow needs no client secret. There is no in-app
override; to change it, edit the constant and rebuild.

The compiled-in registration must exist in the consumers tenant and be
configured as follows — otherwise sign-in fails with the AADSTS code shown
on the Accounts page (700016 = unknown app / wrong tenant, 7000218 =
public client flows disabled):

1. https://portal.azure.com → Microsoft Entra ID → App registrations →
   **New registration**.
2. *Supported account types*: **Personal Microsoft accounts only**
   (consumers) or the multitenant+personal option.
3. Authentication → **Allow public client flows: Yes** (required for
   device-code flow). No redirect URI and no client secret needed.
4. Copy the *Application (client) ID* into `AZURE_CLIENT_ID`.

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
| `Failed to get a resolved OhmUrl for "...index.d.ts"` at CompileArkTS | so-type-package resolution is bypassed entirely: the import types are declared ambiently in `entry/src/main/ets/native/Mc4hosCoreNative.d.ts` (declare module 'mc4hos_core.so'), and entry/oh-package.json5 carries no file: dependency for it. Known contributing factors (entry-level `ohpm install`, `useNormalizedOHMUrl`, lock drift) are documented in the git history |
| `Concurrent function should only use import variable or local variable` | taskpool `@Concurrent` functions may only reference imports/locals — shared helpers must live in an imported module (`DownloadShared.ets`) |
| `Failed to get a resolved OhmUrl for "hvigor_ignore_..."` on `.so` imports | the native module name must match `/^lib\S+\.so/` — rename to `lib<name>.so` (types dir, oh-package name, entry dependency, all ArkTS imports). Root cause found by reading `tsc-resolve.js` in hvigor-arkts-compose |
| `JNI_CreateJavaVM failed (code …)` | JVM built for wrong **ABI** or libc — pack must match `Paths.deviceAbi()` (logged at startup) and be a musl/ohos build |
| Surface stays black, self-test on | EGL config mismatch — try removing alpha bits in `game_surface.cpp` |
| Overlay input ignored | game not running (events before VM start are dropped; check `[MC4HOS] input bridge` line) |
| Downloads stall | `ohos.permission.INTERNET` must be granted (module.json5 already declares it); check `hdc hilog` for HTTP codes |
| `compatibleSdkVersion` error at build | SDK string mismatch — copy the exact string from SDK manager |
| x86_64 emulator crash at JVM load | runtime pack or natives deployed from the ARM tree — both paths are ABI-qualified, see §6 |
| "not enough disk space" in console | asset batch preflight refused; free space or reduce the installed version set |
| `Task timed out` in download log | API 24 taskpool timeout hit — check network/proxy; the worker retries twice before failing |

### Local native verification (no device needed)

The C++ sources can be compiled+linked without DevEco's GUI, mirroring
ninja's flags (useful to iterate on native errors fast):

```bash
SDK="C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/native"
"$SDK/llvm/bin/clang++.exe" --target=x86_64-linux-ohos \
  --sysroot="$SDK/sysroot" -D__MUSL__ -std=gnu++17 -fPIC -fexceptions -frtti \
  -I"C:/Program Files/Huawei/DevEco Studio/sdk/default/hms/native/sysroot/usr/include" \
  -Ientry/src/main/cpp/include -c entry/src/main/cpp/napi_init.cpp -o /tmp/t.o
```

## 9. Compliance checklist for distribution

- Keep the MPL-2.0 header in every modified/added source file (Exhibit A).
- Provide this repository's source (MPL §3.2) when distributing HAPs.
- Do **not** redistribute OpenJDK/LWJGL/OpenAL binaries without preserving
  their license texts — build them from pristine upstream sources and ship
  their NOTICE files alongside (see NOTICE.md).
- Never bundle game assets; the launcher fetches them from Mojang's
  official servers only, on behalf of an authenticated, licensed user.

## 10. Continuous integration (zero configuration)

`.github/workflows/ci.yml` runs two jobs on every push/PR — with **no
secrets and no repository variables required**:

1. **verify** — SDK-less sanity gate:
   `python3 scripts/check_mpl_headers.py` (SPDX coverage) and
   `python3 scripts/check_configs.py` (strict-JSON resources, no `#` in
   json5, modelVersion consistency, SDK string format/ordering,
   buildVersion, PNG icons).
2. **build** — full unsigned HAP on GitHub-hosted runners. Before building,
   `scripts/fetch_bundled_jres.py` downloads the pinned runtime packs into
   `entry/src/main/resources/rawfile/jvm/` (cached by
   `scripts/bundled-jres.lock.json`); all packs are required. The HarmonyOS
   toolchain (commandline-tools 6.1.1.280, bundled SDK = API 24, matching
   `modelVersion` 6.1.1) is fetched from **public, login-free sources** —
   Huawei's own download page is login-gated, so the workflow uses a public
   community mirror, pinned to an immutable Hugging Face revision
   (verified downloadable, ~2.1 GB):

   ```
   https://huggingface.co/csukuangfj/harmonyos-commandline-tools/resolve/7ff999061d57e9a542fe7e02fc920961e67a163b/commandline-tools-linux-x64-6.1.1.280.zip
   ```

   The zip is cached via `actions/cache`, so mirror changes don't break
   the pipeline after the first run.

   The zip's internal layout (verified by reading its central directory —
   it differs from DevEco Studio installs, which is why naive detection
   fails):

   ```
   command-line-tools/              <- zip root is HYPHENATED
   ├── bin/hvigorw, bin/ohpm        <- user-facing launchers (added to PATH)
   ├── hvigor/bin/hvigorw.js        <- hvigor engine (no tools/ level)
   ├── tool/node/bin/node           <- bundled node (singular "tool/")
   ├── ohpm/bin/ohpm
   └── sdk/default/{openharmony,hms}
                                    <- incl. hmos.toolchain.cmake + llvm
   ```

   The workflow detects `hvigorw.js` by name anywhere in the extracted
   tree and derives the root from it, so it survives root-name changes. An optional repository VARIABLE
   `HOS_TOOLS_URL` can pin a different toolchain (tried first) — never a
   secret.

**OpenJDK runtime builds (`jdk-ohos.yml`)** live in the separate
[openharmony-openjdk](https://github.com/BytinIsDead/openharmony-openjdk)
repository. That workflow uses the same toolchain zip but builds the JDKs,
not the HAP, for both x86_64 and aarch64. Run it manually with
`publish = true` (or push a `jdk-ohos-v*` tag) to create the `jdk-ohos-v1`
release that the launcher's x86_64 catalog points at. Build inputs are pinned
by SHA-256 in that repository's `build-inputs.lock.json`; the workflow
uploads artifacts on every run and publishes only when asked. See its README
for the GPLv2+CE source-offer obligations.

The produced HAP is **unsigned** (debug signing certificates are
account-bound); signing stays a local manual step (§2). For local builds
without GitHub, `scripts/build_hap.bat` / `scripts/build_hap.sh` drive the
locally installed DevEco Studio the same way.

When a newer commandline-tools release lands on the mirror, bump the two
URLs in `ci.yml` (one-line change) and the cache key.

## 11. HarmonyOS 6.1.1 (API 24) capability notes

Verified against the local SDK (`sdk/default/openharmony/ets/oh-uni-package.json`:
`apiVersion: "24"`, `version: "6.1.1.125"`, Release) and a local
`assembleHap` build with DevEco Studio 6.1.1.

| API (since 24 unless noted) | Where used |
|---|---|
| `taskpool.Configs` + `execute(task, configs)` (priority, timeout) | `download/DownloadManager.ets` — bulk downloads carry an explicit priority and a 10-minute per-file timeout; timed-out workers are retried |
| `hidebug.getRssInfo()` | Settings → Diagnostics (process RSS + swap, KB→MB) |
| `util.ArkTSVM.getAllVMHeapMemoryInfo()` | Settings → Diagnostics (heap object totals) |
| `util.ArkTSVM.onVMHeapMemoryPressure()` | `entryability/EntryAbility.ets` (logs local/shared/process pressure) |
| `storageStatistics.getFreeSizeSync()` (15) / `getFreeInodes()` (24) | disk preflight in `GameInstaller` and Diagnostics |
| DevEco 6.1.1 Hot Reload (C++ + resources) | faster iteration on `entry/src/main/cpp` |

Protocol/correctness fixes that matter on this toolchain:

- Modern version JSON references `${classpath}` and `${natives_directory}`;
  both are now substituted by `JvmArgumentBuilder`. The native loader drops
  the version's `-cp`/`-classpath` pair and its own
  `-Djava.library.path`/`-Djava.class.path` duplicates so the launcher stays
  the single owner of those values. Unknown JVM options are tolerated
  (`ignoreUnrecognized = JNI_TRUE`) because descriptors may target a newer
  JDK than the installed runtime.
- The asset index is fetched from its full `assetIndex.url` (a
  `piston-meta/v1/packages/<sha1>/<id>.json` file URL) and verified against
  `assetIndex.sha1`; the previous code appended the id to that full URL.
- Overlay input is dispatched continuously by a dedicated JNI thread (not
  only once at startup), and the Java ring buffer writes at the head/tail
  pair boundary.
- Surface geometry is queried before the self-test renderer starts, and
  every create/resize notifies `PlatformBridge.onGameSurfaceChanged`.
- `latest.log` is opened when the launch config supplies the log directory;
  the early `initialize()` call no longer prevents it.

Java runtime requirements (from live Mojang metadata): the current release
(26.x) requires **Java 25**, 1.20.5–1.21.x require **Java 21**, and 1.12.2
requires **Java 8**. The runtime catalog covers aarch64 Java 8/17/21/25 and
x86_64 Java 21/25, filters by device ABI, verifies the pack size and
SHA-256, discovers the JDK8 or modern `libjvm.so` layout, and never selects
an older major than the game requires. aarch64 packs are bundled in the HAP
and extracted before any download is attempted; the same verification runs
on the extracted copy.

Limitation: the JVM is linked in-process, so `System.exit` (used by "Leave
game") terminates the app process. A restartable/background game session
needs a separate process (`Ability`/service) hosting the JVM.
