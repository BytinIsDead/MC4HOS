<!--
Copyright (C) 2026 MC4HOS Contributors
SPDX-License-Identifier: MPL-2.0-no-copyleft-exception

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
-->
# MC4HOS — Third-Party Notices

MC4HOS is licensed under the **Mozilla Public License 2.0 with the Exhibit B
"Incompatible With Secondary Licenses" notice appended** — SPDX expression
`MPL-2.0-no-copyleft-exception`. In plain terms: original Covered Files stay
MPL-2.0, and downstream Works may NOT combine them with code licensed under
the Apache License 2.0 or other Secondary Licenses. Third-party files retain
their own licenses and notices. The repository has these notice exceptions:

1. **Strict-JSON resource files** (`**/resources/**/*.json`,
   `**/resources/base/profile/*.json`) are parsed by HarmonyOS tooling with a
   strict JSON parser that rejects comments, so they cannot carry inline
   notices. Per MPL-2.0 Exhibit A, their license notice is conveyed by this
   NOTICE file and the repository-root `LICENSE`.
2. **Machine-generated files** (build outputs under `build/`, `.cxx/`,
   `.build/`, caches under `.hvigor/`/`.idea/`, `oh_modules/`, `*-lock.json5`,
   and hvigor/IDE-regenerated configs) are derived artifacts, not Covered Code;
   notice for them is conveyed the same way. If DevEco Studio strips the
   header from a hand-maintained config (`build-profile.json5`,
   `hvigor/hvigor-config.json5`) during normalization, re-add it.
3. **Vendored third-party source** retains its upstream license rather than
   being relicensed as MPL. This includes the unmodified Oracle JNI headers
   under `entry/src/main/cpp/meowcraftbridge/`, the BSD-3-Clause LWJGL overlay
   sources under `scripts/native/lwjgl/overlay*`, and the LGPL-2.0-or-later
   OpenAL OHAudio backend under `scripts/native/openal/ohaudio/`. The
   Harmomeow-derived bridge files identify their original MIT terms and the
   MC4HOS adaptation terms in each file header.

The launcher itself is clean-room, original code. It does **not** contain or
distribute any Mojang Studios or Microsoft proprietary code, assets, or artwork,
and it is not affiliated with, endorsed by, or connected to Mojang Studios,
Microsoft, or OpenHarmony/Huawei.

At runtime the launcher *downloads from official servers* (at the direction of
the signed-in user, who must own a licensed copy of the game) and *executes*
the following third-party components. Generated native artifacts are not
committed; the HAP build packages them into `entry/libs/<abi>/` and the adapted
LWJGL JAR into `resources/rawfile/bridge/`. Anyone distributing those binaries
must satisfy the licenses below, including corresponding-source and relinking
terms where applicable.

| Component | Role | License | Upstream |
|---|---|---|---|
| OpenJDK (aarch64 / x86_64 OpenHarmony builds) | Embedded Java runtime executing the game | GPLv2 + Classpath Exception | https://openjdk.org |
| LWJGL 3.4.3 and adapted GLFW overlay | Java-side OpenGL/OpenAL bindings used by the game | BSD-3-Clause | https://lwjgl.org |
| Harmomeow native GLFW/EGL bridge | XComponent surface, GLFW callbacks and input | MIT; MC4HOS adaptations MPL-2.0-no-copyleft-exception | Reference revision `08cc55f66bed1bba931d6f6aa0507f6adeef9b3f` |
| libffi 3.8.0 | LWJGL native callbacks, statically linked into LWJGL core | MIT | https://github.com/libffi/libffi |
| OpenAL Soft 1.24.3 with OHAudio/OpenSL backends | Audio backend (`libopenal.so`) | LGPL-2.0-or-later | https://openal-soft.org |
| FreeType | Font rendering, supplied by the OpenJDK runtime packs | FreeType License (FTL) | https://freetype.org |
| Oracle JNI headers | Native/JVM ABI declarations | GPLv2 + Classpath Exception | https://openjdk.org |
| gl4es / GL-on-GLES translation layer (optional, not packaged) | Desktop GL → OpenGL ES translation | MIT | https://github.com/ptitSeb/gl4es |

Additional notices for code linked into the native artifacts are preserved in
`scripts/licenses/` and copied into the HAP under
`resources/rawfile/licenses/`: `{fmt}` (MIT), PFFFT (BSD-style), liburing (MIT),
stb_image (MIT or public domain), and tinyfiledialogs (Zlib).

## Native stack provenance and corresponding source

The native stack is built for both `arm64-v8a` and `x86_64` from these pinned
inputs:

- LWJGL 3.4.3, commit
  `30fac9b95f99cda97312232be25ba55297bf9951`.
- libffi 3.8.0, commit
  `12ffd1f9dc56fcea79d2f742f424301ae668d663`.
- OpenAL Soft 1.24.3 source archive
  `https://github.com/kcat/openal-soft/archive/refs/tags/1.24.3.tar.gz`,
  SHA-256 `7e1fecdeb45e7f78722b776c5cf30bd33934b961d7fd2a11e0494e064cc631ce`.

Reproducible builders and all MC4HOS/Harmomeow adaptation sources are in
`scripts/native/lwjgl/` and `scripts/native/openal/`. The LWJGL builder fetches
the official Maven release JARs, verifies their published SHA-1 values, applies
the included GLFW overlay, and builds core/OpenGL/STB/tinyfd natives with libffi.
The OpenAL builder patches a fresh extraction for the HarmonyOS OpenSL backend,
installs the OHAudio backend, and exports the `ALC_SOFT_system_events` entry
points.

For **OpenAL Soft**, complete corresponding source consists of the pinned
archive above plus the files under `scripts/native/openal/`. Run
`scripts/native/build_stack.sh --sdk-native <OHOS-SDK-native> --abi x86_64` or
`--abi arm64-v8a`; the wrapper extracts a fresh source tree for each ABI. The
builders produce a relinkable `libopenal.so` with the same soname and record
the required SDK/toolchain inputs. The full LGPLv2 text is
`scripts/licenses/OpenAL-COPYING.txt`; PFFFT and `{fmt}` notices accompany it.
This source offer has no expiration. Redistributors must preserve these license
files, the source identities, the modification notices, and the ability to
relink the OpenAL library.

LWJGL, libffi, Harmomeow bridge code, stb, tinyfd and liburing are permissively
licensed; their full notices are in `scripts/licenses/` and in the HAP. The
Oracle JNI headers remain under GPLv2 with the Classpath Exception and are
covered by the OpenJDK license material below.

## Bundled OpenJDK runtimes

The build scripts in the separate
[`openharmony-openjdk`](https://github.com/BytinIsDead/openharmony-openjdk)
repository are original MC4HOS code under this repository's MPL-2.0 terms
(`openharmony-jdk/` here is a reference copy). They **download** the third-party
OpenJDK source and the OHOS patch/stub archives at build time; those archives
and the resulting JDK images are GPLv2+CE works and are never committed.

The default build bundles the pinned runtime archives for aarch64 Java
8/17/21/25 and x86_64 Java 21/25, but packages native libraries and selects a
loadable runtime for Java 21 only. The HAP redistributes all bundled OpenJDK
packs, so GPLv2+CE redistribution terms apply to those parts. The build writes
`resources/rawfile/jvm/OpenJDK-LICENSE.txt` (GPLv2 plus the
Classpath Exception appendix) and `RUNTIME-NOTICES.txt` next to the packs,
naming each pack's pinned source identity; the launcher copies both into the
extracted runtime. The JDK8 pack additionally keeps its upstream `jre/LICENSE`
and `jre/ASSEMBLY_EXCEPTION`.

Corresponding source for the GPLv2+CE code in a bundled pack:

- x86_64 packs record the upstream source repositories, commits and pinned
  build-input archives in their `MC4HOS-RUNTIME-NOTICE.txt` and the
  openharmony-openjdk repository's `build-inputs.lock.json`.
- aarch64 packs come unmodified from the pinned public community releases
  listed in `scripts/bundled-jres.lock.json`; use the source identities those
  releases publish, or request the corresponding source from the distributor.

The full GPLv2 text shipped in the HAP, the pinned identities above, and the
source offer to any recipient satisfy GPLv2 section 3. Redistributors who
modify this project must preserve the license files, the pack notices and
that offer; the Classpath Exception does not remove these GPL obligations.

**Trademark notice:** *Minecraft* is a trademark of Mojang Synergies AB. The
name "MC4HOS" refers to this launcher in a purely descriptive, nominative
sense. Users must comply with the Minecraft EULA (https://aka.ms/MinecraftEULA)
and must already own the game; this launcher contains no game content.

**Azure application notice:** Microsoft authentication uses a public OAuth
client id compiled into the app (`AZURE_CLIENT_ID`); it is not a secret and
device-code flow needs no client secret. Sign-in goes directly to
Microsoft's documented endpoints; see `docs/BUILD.md` §7.
