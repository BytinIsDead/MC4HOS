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
3. **No secrets**: no client secrets, certificates, tokens or account data.
   The Microsoft OAuth *public client* id (`AZURE_CLIENT_ID`) is not a
   secret and is compiled in; never add a client secret (docs/BUILD.md §7).

## AI-assisted contributions

AI tools are allowed, with conditions:

- **You own the change.** Read, understand and be able to explain every line
  you submit. You are responsible for its correctness, licensing and security.
- **Verify APIs, flags and paths** against the installed SDK or upstream
  documentation. Generated code that merely looks plausible is not evidence.
- **Disclose AI assistance** in the PR description (tool and extent). Using AI
  is fine; submitting unreviewed output is not.
- **Do not paste secrets, tokens, certificates, account data, proprietary or
  decompiled code, or game assets** into AI tools.
- AI output follows the same clean-room, license-header and testing rules as
  hand-written code.

## Testing before every commit (required)

A runtime change that has not been tested on real hardware or an emulator must
not be committed.

Before committing any code, native, resource or configuration change:

1. Build the HAP (`scripts/build_hap.bat` / `.sh`) and fix every error.
2. Compile both native ABIs when the change touches native code.
3. Install and run it on a **real HarmonyOS device or an emulator**.
4. Exercise the feature you changed, including at least one failure or edge
   path, and smoke-test the core flows (runtime selection and launch).
5. Include the device/emulator model, API version, steps and result in the PR
   description. "It compiles" and "CI passed" are not testing.

Documentation-only commits are exempt from device testing but still must pass
the header and config checks. If you cannot test, **do not commit** — ask a
maintainer or another contributor to test first.

Useful device checklist:

- cold launch, runtime/Java selection, and runtime download or local import;
- create a profile and reach the game title screen;
- keyboard, mouse/touch and controller input reach the game;
- audio works and the app survives backgrounding/resume;
- a failed download or missing runtime shows an error instead of crashing;
- log output identifies the chosen runtime and native library versions.

## Strict commit rules

- `main` must build and pass all checks at every commit. Never push a broken
  commit with the intention of fixing it later.
- One logical change per commit. Do not mix refactors, features and fixes, and
  do not include unrelated formatting or drive-by edits.
- Never bypass hooks or CI: no `--no-verify`, no skipped tests, no disabled
  checks. Fix the root cause.
- Commit no build output, dependencies, caches, secrets, keys, tokens,
  third-party runtime binaries, Minecraft/Mojang/Microsoft assets or code.
- Never force-push or rewrite history on `main`. If a commit is wrong, revert
  it with a new commit; do not layer hacks on top.
- Stage files by name and review `git diff --staged` plus `git status` before
  committing.
- Preserve license headers and notices. Changes to licensing, permissions or
  the build configuration require maintainer agreement.
- Update tests and documentation in the same commit as the behaviour change.
- When unsure, stop and open an issue instead of guessing.

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
| ArkTS `Record<string, Object>` literals | values must be object **references** — primitives/arrays are rejected as "untyped"; use a declared interface or bracket assignment (`payload['key'] = v`) |
| `XComponent({...})` on API 24 | classic overload field is **`libraryname`** (not `library`); `XComponentOptions` takes `type` + required `controller` |
| `emitter.on(event, cb)` | `cb` must be a **non-null** local — nullable `\| null` fields fail every overload |
| Native module names | the import specifier and oh-package name **MUST start with `lib`** (`libmc4hos_core.so`) — hvigor's resolver fast-paths `/^lib\S+\.so/` only; other names fail OhmUrl resolution (root cause of 9 failed CI runs) |

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

CI is necessary but not sufficient: attach the device/emulator test result
(see the checklist above) to every PR that changes runtime behaviour. A PR
without test evidence is not ready for review.

## Native code

- The OHOS NDK ships no `jni.h` — use `entry/src/main/cpp/include/jni_compat.h`
  (clean-room ABI subset). Never include `<jni.h>`, never vendor JDK headers.
- Keep CMake status messages ASCII-only.
- Test both ABIs (`arm64-v8a`, `x86_64`) — the fastest loop is the direct
  clang invocation documented in docs/BUILD.md ("Local native verification").

## Commits

Small, focused commits; imperative subject lines (`Fix X`, `Add Y`);
reference the failing error code when a change resolves a build issue.
Never commit untested changes, never bypass hooks, and never push a red
build to `main` — see the strict commit rules above.
