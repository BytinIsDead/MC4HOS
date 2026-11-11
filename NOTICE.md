<!--
Copyright (C) 2026 MC4HOS Contributors
SPDX-License-Identifier: MPL-2.0

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
-->
# MC4HOS — Third-Party Notices

MC4HOS is licensed under the **Mozilla Public License 2.0** (see `LICENSE`).
Every source file carries the Exhibit-A notice, with two documented
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
the following third-party components, which are **not included in this
repository** and must be built from their pristine upstream sources by anyone
distributing MC4HOS binaries:

| Component | Role | License | Upstream |
|---|---|---|---|
| OpenJDK (aarch64, OpenHarmony build) | Embedded Java runtime executing the game | GPLv2 + Classpath Exception | https://openjdk.org |
| LWJGL 3 (OpenHarmony build) | Java-side OpenGL/OpenAL bindings used by the game | BSD-3-Clause | https://lwjgl.org |
| OpenAL Soft (OpenHarmony build) | Audio backend (`libopenal.so`) | LGPL-2.1 (or later) | https://openal-soft.org |
| gl4es / GL-on-GLES translation layer (optional) | Desktop GL → OpenGL ES translation for `libGL.so` | MIT | https://github.com/ptitSeb/gl4es |

Distribution obligations (offer of source, license text preservation, and
NOTICE propagation) apply to those binaries per their respective licenses.

**Trademark notice:** *Minecraft* is a trademark of Mojang Synergies AB. The
name "MC4HOS" refers to this launcher in a purely descriptive, nominative
sense. Users must comply with the Minecraft EULA (https://aka.ms/MinecraftEULA)
and must already own the game; this launcher contains no game content.

**Azure application notice:** Microsoft authentication requires your own
Azure AD application registration (device-code flow enabled). MC4HOS ships
**no** client secret or client id; see `docs/BUILD.md` §7.
