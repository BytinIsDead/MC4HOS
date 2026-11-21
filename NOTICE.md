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
`MPL-2.0-no-copyleft-exception`. In plain terms: Covered Files stay MPL-2.0,
and downstream Works may NOT combine them with code licensed under the
Apache License 2.0 or other Secondary Licenses. Every source file carries
the Exhibit-A notice with the matching SPDX identifier; two documented
exemptions:

1. **Strict-JSON resource files** (`**/resources/**/*.json`,
   `**/resources/base/profile/*.json`) are parsed by HarmonyOS tooling with
   a strict JSON parser that rejects comments, so they cannot carry inline
   notices. Per MPL-2.0 Exhibit A, their license notice is conveyed by this
   NOTICE file and the repository-root `LICENSE`.
2. **Machine-generated files** (build outputs under `build/`, `.cxx/`,
   caches under `.hvigor/`/`.idea/`, `oh_modules/`, `*-lock.json5`, and
   hvigor/IDE-regenerated configs) are derived artifacts, not Covered Code;
   notice for them is conveyed the same way. If DevEco Studio strips the
   header from a hand-maintained config (`build-profile.json5`,
   `hvigor/hvigor-config.json5`) during normalization, re-add it.

All other files (`.ets`, `.ts`, `.cpp`, `.h`, `.java`, `.json5`, `.md`,
CMake, docs) carry the inline Exhibit-A header.

The launcher itself is clean-room, original code. It does **not** contain or
distribute any Mojang Studios or Microsoft proprietary code, assets, or artwork,
and it is not affiliated with, endorsed by, or connected to Mojang Studios,
Microsoft, or OpenHarmony/Huawei.

At runtime the launcher *downloads from official servers* (at the direction of
the signed-in user, who must own a licensed copy of the game) and *executes*
the following third-party components, which are **not committed to this
repository**. Binary distributions may bundle them: the build scripts fetch
the pinned runtime archives at build time
(`scripts/bundled-jres.lock.json`). Anyone distributing those binaries must
satisfy the licenses below, including the corresponding-source offer for
OpenJDK.

| Component | Role | License | Upstream |
|---|---|---|---|
| OpenJDK (aarch64 / x86_64 OpenHarmony builds) | Embedded Java runtime executing the game | GPLv2 + Classpath Exception | https://openjdk.org |
| LWJGL 3 (OpenHarmony build) | Java-side OpenGL/OpenAL bindings used by the game | BSD-3-Clause | https://lwjgl.org |
| OpenAL Soft (OpenHarmony build) | Audio backend (`libopenal.so`) | LGPL-2.1 (or later) | https://openal-soft.org |
| gl4es / GL-on-GLES translation layer (optional) | Desktop GL → OpenGL ES translation for `libGL.so` | MIT | https://github.com/ptitSeb/gl4es |

Distribution obligations (offer of source, license text preservation, and
NOTICE propagation) apply to those binaries per their respective licenses.

The build scripts in `openharmony-jdk/` are original MC4HOS code under this
repository's MPL-2.0 terms. They **download** the third-party OpenJDK source
and the OHOS patch/stub archives at build time; those archives and the
resulting JDK images are GPLv2+CE works and are never committed.

When runtime packs are bundled into the HAP (the default build for aarch64
Java 8/17/21/25; x86_64 21/25 once the `jdk-x86_64-v1` release exists), the
HAP redistributes OpenJDK, so GPLv2+CE redistribution terms apply to those
parts. The build writes `resources/rawfile/jvm/OpenJDK-LICENSE.txt` (GPLv2
plus the Classpath Exception appendix) and `RUNTIME-NOTICES.txt` next to the
packs, naming each pack's pinned source identity; the launcher copies both
into the extracted runtime. The JDK8 pack additionally keeps its upstream
`jre/LICENSE` and `jre/ASSEMBLY_EXCEPTION`.

Corresponding source for the GPLv2+CE code in a bundled pack:

- x86_64 packs record the upstream source repositories, commits and pinned
  build-input archives in their `MC4HOS-RUNTIME-NOTICE.txt` and
  `openharmony-jdk/build-inputs.lock.json`.
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

**Azure application notice:** Microsoft authentication requires your own
Azure AD application registration (device-code flow enabled). MC4HOS ships
**no** client secret or client id; see `docs/BUILD.md` §7.
