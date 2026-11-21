<!--
Copyright (C) 2026 MC4HOS Contributors
SPDX-License-Identifier: MPL-2.0-no-copyleft-exception

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
-->
# OpenHarmony OpenJDK for x86_64

This directory is the **separate build tree** for the x86_64 OpenHarmony Java
runtime used by MC4HOS. It is intentionally not part of the ArkTS application
build: it produces standard runtime zips that MC4HOS imports or downloads, and
none of its output is committed to this repository.

The only public OHOS OpenJDK artifacts available at the time of writing are
aarch64 builds, so this tree cross-compiles the same pinned upstream JDK
sources and the same OHOS patch series for `x86_64-linux-ohos`. GitHub Actions
runs the build in `.github/workflows/jdk-x86_64.yml`.

## What gets built

| Pack | Java | Target triple | Pack name |
|---|---|---|---|
| Runtime | 21 | `x86_64-linux-ohos` (musl) | `jre21-ohos-x86_64.zip` |
| Runtime | 25 | `x86_64-linux-ohos` (musl) | `jre25-ohos-x86_64.zip` |

Each zip contains a complete JDK image rooted at the archive root
(`bin/`, `lib/`, `legal/`, `release`). MC4HOS writes its own `runtime.json`
marker after extraction, so the pack itself carries no install state.

## Inputs are pinned, not vendored

`build-inputs.lock.json` pins two public community build-input archives by
SHA-256:

- `jdk21-ohos-20261027-code2-build-inputs.zip`
- `jdk25-ohos-20261027-code1-build-inputs.zip`

Those archives contain the OHOS source patches, CUPS/Fontconfig/X11 stub
headers, and the C++ ABI facade source. They are **GPLv2 + Classpath
Exception** material derived from OpenJDK. They are downloaded at build time,
never committed, and their license files are preserved in the produced pack.

The OpenJDK sources are cloned from the upstream repositories at the commits
recorded in `prebuilt/jdk/build-inputs.json` inside those archives:

| JDK | Repository | Commit |
|---|---|---|
| 21 | `https://github.com/openjdk/jdk21u.git` | `dfcd8d2eecfe62e91070244d8eb10906dc3c812d` |
| 25 | `https://github.com/openjdk/jdk25u.git` | `e8f9ebe5ea813b675410a89fbfafa22e42c04e6a` |

## Build locally (Linux x86_64)

Requirements: Linux, Python 3, a C/C++ host toolchain (`build-essential`),
`autoconf`, `zip`, `unzip`, `libasound2-dev`, a boot JDK matching the target
major (Temurin 21 or 25), and the HarmonyOS command-line tools / SDK containing
`native/`.

```bash
# 1. Get the OHOS command-line tools (same public archive CI uses), unpack it,
#    and locate the native SDK root:
export OHOS_NATIVE=/path/to/commandline-tools/sdk/default/openharmony/native

# 2. Fetch the pinned patch/stub archive for the target major:
python3 openharmony-jdk/scripts/fetch_inputs.py --major 21 \
  --dest /tmp/jdk21-inputs

# 3. Cross-compile and package:
JAVA_HOME=/path/to/temurin-21 \
openharmony-jdk/scripts/build_x86_64.sh \
  --major 21 \
  --native "$OHOS_NATIVE" \
  --inputs /tmp/jdk21-inputs \
  --work /tmp/jdk21-build \
  --output /tmp/jdk21-out
```

The output is `/tmp/jdk21-out/jre21-ohos-x86_64.zip`, its `.sha256` file, and a
one-entry `runtime-catalog-21.json`.

To build 25 instead, pass `--major 25` and use a Temurin 25 `JAVA_HOME`.

## Importing on device

The pack can be pushed and imported without a release:

```bash
hdc file send /tmp/jdk21-out/jre21-ohos-x86_64.zip /data/local/tmp/
# Settings → Deployment → Import runtime pack → jre21-ohos-x86_64.zip
```

## Publishing from GitHub Actions

Run **Actions → OpenJDK x86_64 runtime → Run workflow** with
`publish = true`. The workflow builds both majors, merges the catalogs, and
uploads the zips, `SHA256SUMS`, and `runtime-catalog.json` to a release tagged
`jdk-x86_64-v1` (or the tag you provide). MC4HOS's built-in x86_64 catalog
entries point at that release tag.

If the repository is private, release assets require authentication and the
in-app downloader cannot fetch them; use the `hdc` import above instead.

## Licensing

OpenJDK is **GPLv2 with the Classpath Exception**. The runtime packs are
separate works, not part of the MPL-2.0 MC4HOS application. Every pack includes:

- the upstream `LICENSE`, `ADDITIONAL_LICENSE_INFO`, and `ASSEMBLY_EXCEPTION`;
- the OHOS SDK `NOTICE.txt` under `legal/amcl-native/`;
- `MC4HOS-RUNTIME-NOTICE.txt` with the exact source repositories, commits, and
  patch-archive identity used for that build.

If you redistribute a pack, keep those files intact and provide the
corresponding source (the pinned upstream commits plus the build-input archive)
as required by GPLv2. Nothing in this directory contains or distributes
Mojang/Microsoft code or game assets.
