<!--
Copyright (C) 2026 MC4HOS Contributors
SPDX-License-Identifier: MPL-2.0-no-copyleft-exception

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
-->

# Contributing to MC4HOS

Thanks for helping build the clean-room HarmonyOS Minecraft launcher.
A few rules keep this project legally clean and buildable — they exist
because each one broke a real build.

## Ground rules

1. **License**: every source file carries the Exhibit-A header with
   `SPDX-License-Identifier: MPL-2.0-no-copyleft-exception`. The project is
   offered without the MPL Secondary Licenses (see NOTICE.md). No GPL-licensed
   material may be committed — third-party runtime components (OpenJDK,
   LWJGL, OpenAL Soft) are built from upstream sources outside this repo and
   documented in NOTICE.md only.
2. **Clean-room**: no proprietary code, no decompiled game code, no game
   assets, no PojavLauncher-derived sources. Implement from public
   documentation only.
3. **No secrets**: no Microsoft client ids, certificates, or account data.
   Each distributor registers their own Azure application
   (docs/BUILD.md §7).

## File-format rules (each broke a real build)

| File type | Rule |
|---|---|
| `resources/**/*.json`, `profile/*.json` | **strict JSON** — no comments at all (restool error 11203002) |
| `*.json5` configs | comments are `//` only — a `#` breaks hvigor's parser |
| `.hvigor/hvigor-config.json5`, `hvigor/hvigor-config.json5`, `oh-package.json5` | `modelVersion` must be identical in all of them and match your DevEco Studio version |
| `build-profile.json5` | SDK strings keep the `"(api)"` suffix (`"6.1.1(24)"`); `compatibleSdkVersion ≤ targetSdkVersion ≤ compileSdkVersion` |
| `AppScope/app.json5` | must declare `buildVersion` (6.x schema) |
| app icons | PNG only (SVG rejected) |
| `AppScope`+`entry` media | app_icon.png committed; SVG not allowed for icons |

DevEco Studio may rewrite these configs during sync (it can drop an explicit
`compileSdkVersion` or strip license headers) — re-add headers if the IDE
removes them; the checks below catch regressions.

## Before opening a PR

```bash
python3 scripts/check_mpl_headers.py   # SPDX coverage
python3 scripts/check_configs.py       # config rules above
```

Both run in the CI `verify` job (`.github/workflows/ci.yml`). The CI
`build` job compiles an unsigned HAP on GitHub using a public, pinned
commandline-tools mirror — no secrets or repository variables needed. For
local builds use `scripts/build_hap.bat` / `scripts/build_hap.sh`.

## Native code

- The OHOS NDK ships no `jni.h` — use `entry/src/main/cpp/include/jni_compat.h`
  (clean-room ABI subset). Never include `<jni.h>`, never vendor JDK headers.
- Keep CMake status messages ASCII-only.
- Test both ABIs (`arm64-v8a`, `x86_64`) — the fastest loop is the direct
  clang invocation documented in docs/BUILD.md ("Local native verification").

## Commits

Small, focused commits; imperative subject lines (`Fix X`, `Add Y`);
reference the failing error code when a change resolves a build issue.
