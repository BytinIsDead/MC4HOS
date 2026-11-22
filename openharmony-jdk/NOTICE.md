<!--
Copyright (C) 2026 MC4HOS Contributors
SPDX-License-Identifier: MPL-2.0-no-copyleft-exception

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
-->
# Notices

The build scripts, workflow, and documentation in this repository are original
MC4HOS code under **MPL-2.0** (SPDX: `MPL-2.0-no-copyleft-exception`); see
[LICENSE](LICENSE).

## OpenJDK runtime packs (release assets)

This repository builds and releases OpenJDK runtime packs. Those binaries are
**GPLv2 + Classpath Exception** works, not MPL-2.0, and are not committed to
this repository. Each pack contains:

- upstream `LICENSE`, `ADDITIONAL_LICENSE_INFO`, `ASSEMBLY_EXCEPTION`;
- OHOS SDK `NOTICE.txt` under `legal/amcl-native/`;
- `MC4HOS-RUNTIME-NOTICE.txt` naming the upstream repository, exact commit,
  and the SHA-256-pinned build-input archive (patches, stubs, C++ ABI facade).

Corresponding source for a pack is the pinned upstream commit plus the pinned
build-input archive listed in `build-inputs.lock.json` and in the pack notice.
Redistributors must preserve those files and that offer (GPLv2 §3). The
Classpath Exception does not remove these obligations.

The OpenJDK source, build-input archives, and produced JDK images are never
committed here; the build downloads them at build time. No Mojang/Microsoft
code or Minecraft assets are present.
