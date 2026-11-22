<!--
Copyright (C) 2026 MC4HOS Contributors
SPDX-License-Identifier: MPL-2.0-no-copyleft-exception

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
-->
# OpenHarmony OpenJDK for x86_64

Cross-build tree for the **x86_64 and aarch64 OpenHarmony Java runtimes** used
by [MC4HOS](https://github.com/BytinIsDead/MC4HOS). It produces standard runtime
packs; the build scripts and workflows are MPL-2.0 code, the produced JDK
images are GPLv2 + Classpath Exception works distributed as release assets
(never committed).

Public aarch64 OHOS OpenJDK builds exist upstream, but this tree builds both
targets from the same pinned sources and patches so the two ABIs share one
provenance: pinned upstream JDK sources plus the OHOS patch series, for
`x86_64-linux-ohos` and `aarch64-linux-ohos` (musl).

## What gets built

| Pack | Java | Target triple | Asset name |
|---|---|---|---|
| Runtime | 21 | `x86_64-linux-ohos` (musl) | `jre21-ohos-x86_64.zip` |
| Runtime | 25 | `x86_64-linux-ohos` (musl) | `jre25-ohos-x86_64.zip` |
| Runtime | 21 | `aarch64-linux-ohos` (musl) | `jre21-ohos-aarch64.zip` |
| Runtime | 25 | `aarch64-linux-ohos` (musl) | `jre25-ohos-aarch64.zip` |

Each zip contains a runtime image rooted at the archive root (`bin/`, `lib/`,
`conf/`, `legal/`, `release`); developer-only payload (jmods, sources, demos,
headers) is pruned at packaging time. MC4HOS writes its own `runtime.json`
marker after extraction, so the pack itself carries no install state.

## Release

`.github/workflows/jdk-ohos.yml` builds both majors for both ABIs and
publishes them to the `jdk-ohos-v1` release:

- `jre21-ohos-x86_64.zip`, `jre25-ohos-x86_64.zip`
- `jre21-ohos-aarch64.zip`, `jre25-ohos-aarch64.zip`
- `runtime-catalog.json` with name / ABI / size / SHA-256 / pack URL
- `SHA256SUMS`

Run **Actions → OpenJDK OHOS runtimes → Run workflow** with
`publish = true`. Pushing a `jdk-ohos-v*` tag builds and publishes too.

## Consumed by MC4HOS

MC4HOS pins every pack in `scripts/bundled-jres.lock.json` (size and
SHA-256) and fetches the x86_64 packs from this release at HAP build time
(`scripts/fetch_bundled_jres.py`), verifying the digests again at install
time. The release `runtime-catalog.json` is consulted for packs that lack a
pinned digest. Without a bundled pack the launcher downloads it from the
release; packs can also be imported over `hdc` from `/data/local/tmp`.

## Inputs are pinned, not vendored

`build-inputs.lock.json` pins two public community build-input archives by
SHA-256:

- `jdk21-ohos-20261027-code2-build-inputs.zip`
- `jdk25-ohos-20261027-code1-build-inputs.zip`

Those archives contain the OHOS source patches, CUPS/Fontconfig/X11 stub
headers, and the C++ ABI facade source. They are **GPLv2 + Classpath
Exception** material derived from OpenJDK: downloaded at build time, never
committed, license files preserved in the produced pack.

The OpenJDK sources are cloned from upstream at the commits recorded in
`prebuilt/jdk/build-inputs.json` inside those archives:

| JDK | Repository | Commit |
|---|---|---|
| 21 | `https://github.com/openjdk/jdk21u.git` | `dfcd8d2eecfe62e91070244d8eb10906dc3c812d` |
| 25 | `https://github.com/openjdk/jdk25u.git` | `e8f9ebe5ea813b675410a89fbfafa22e42c04e6a` |

`scripts/patches/<major>/` carries small upstream-compatible fixups applied
after the community patch series; a fixup is skipped when the pinned commit
already contains it. It currently holds the glibc 2.42 `uabs` name-collision
rename (`uabs` → `g_uabs`, upstream JDK-8354941) needed by the JDK 21 pin, a
`<stdbool.h>` include for the OHOS JavaSound port helper, whose SDK headers use
`bool` from plain C, and a JDK 21 `adlc` fix that initializes all `FrameForm`
fields (aarch64 defines no `cisc_spilling_operand_name`, and the uninitialized
field made `adlc` hash heap garbage and crash during the cross-build). JDK 25
already initializes these fields.

## Build locally (Linux x86_64)

Requirements: Linux, Python 3, a C/C++ host toolchain (`build-essential`),
`autoconf`, `zip`, `unzip`, `libasound2-dev`, GNU coreutils (not the uutils
variant shipped by Ubuntu 25.10+), a boot JDK matching the target
major (Temurin 21 or 25), and the HarmonyOS command-line tools / SDK containing
`native/`.

```bash
# 1. Unpack the OHOS command-line tools and locate the native SDK root:
export OHOS_NATIVE=/path/to/commandline-tools/sdk/default/openharmony/native

# 2. Fetch the pinned patch/stub archive for the target major:
python3 scripts/fetch_inputs.py --major 21 --dest /tmp/jdk21-inputs

# 3. Cross-compile and package (add --arch aarch64 for ARM):
JAVA_HOME=/path/to/temurin-21 scripts/build_ohos_jre.sh \
  --major 21 \
  --arch x86_64 \
  --native "$OHOS_NATIVE" \
  --inputs /tmp/jdk21-inputs \
  --work /tmp/jdk21-build \
  --output /tmp/jdk21-out
```

The output is `/tmp/jdk21-out/jre21-ohos-x86_64.zip`, its `.sha256` file, and a
one-entry `runtime-catalog-21-x86_64.json`. For Java 25, pass `--major 25`
with a Temurin 25 `JAVA_HOME`; for ARM use `--arch aarch64`.

## Licensing

OpenJDK is **GPLv2 with the Classpath Exception**. The runtime packs are
separate works, not part of the MPL-2.0 build scripts. Every pack includes:

- the upstream `LICENSE`, `ADDITIONAL_LICENSE_INFO`, and `ASSEMBLY_EXCEPTION`;
- the OHOS SDK `NOTICE.txt` under `legal/amcl-native/`;
- `MC4HOS-RUNTIME-NOTICE.txt` with the exact source repositories, commits, and
  patch-archive identity used for that build.

If you redistribute a pack, keep those files intact and provide the
corresponding source (the pinned upstream commits plus the pinned build-input
archive) as required by GPLv2. See [NOTICE.md](NOTICE.md).
