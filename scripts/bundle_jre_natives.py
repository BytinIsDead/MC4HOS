#!/usr/bin/env python3
# Copyright (C) 2026 MC4HOS Contributors
# SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

"""Extracts the JRE native libraries into the module's libs/<abi> folders.

HarmonyOS only lets the dynamic linker load shared libraries that live inside
the HAP (`/data/storage/el1/bundle/libs/<abi>/`); a `.so` extracted into the
app sandbox cannot be dlopen'ed even with the executable bit set. The runtime
packs are still extracted to the sandbox for `lib/modules`, `conf/` and the
other plain files, but the JRE's native libraries are packaged in the HAP
itself by this script and loaded from there by libmc4hos_core.

Only one Java major can own the flat `libs/<abi>/` namespace, because every
OpenJDK build ships the same sonames (libjvm.so, libjava.so, ...). The pack
selected here (Java 21 by default) is therefore the only runtime MC4HOS can
boot on this platform.

Run after fetch_bundled_jres.py: it reads the pack zips from the rawfile
directory and writes entry/libs/<abi>/, which is generated and never committed.
"""

import argparse
import json
import pathlib
import sys
import zipfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
LOCK = HERE / "bundled-jres.lock.json"
PACKS = ROOT / "entry/src/main/resources/rawfile/jvm"
DEST = ROOT / "entry/libs"
ABIS = ("arm64-v8a", "x86_64")
# The HAP already carries the NDK's libc++_shared.so; a second copy would
# collide at packaging time, and the JRE was built against the same OHOS NDK.
SKIP_NAMES = {"libc++_shared.so"}
MANIFEST = DEST / ".jre-natives.json"


def pack_natives(zip_path: pathlib.Path) -> dict:
    """Returns {basename: bytes} for every .so under lib/ or jre/lib/."""
    out = {}
    with zipfile.ZipFile(zip_path) as archive:
        for info in archive.infolist():
            name = info.filename
            if not name.endswith(".so"):
                continue
            if not (name.startswith("lib/") or name.startswith("jre/lib/")):
                continue
            base = pathlib.PurePosixPath(name).name
            if base in SKIP_NAMES or base in out:
                continue
            out[base] = archive.read(info)
    return out


def clear_previous(dest: pathlib.Path) -> None:
    """Deletes only the files listed in the manifest of the previous run."""
    if not MANIFEST.is_file():
        return
    try:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        manifest = {}
    for abi, files in manifest.get("abis", {}).items():
        for name in files:
            path = dest / abi / name
            if path.is_file():
                path.unlink()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dest", type=pathlib.Path, default=DEST)
    parser.add_argument("--lock", type=pathlib.Path, default=LOCK)
    parser.add_argument("--packs", type=pathlib.Path, default=PACKS)
    parser.add_argument("--major", type=int, default=21,
                        help="Java major whose natives are packaged (default: 21)")
    parser.add_argument("--abi", default="both", choices=("both",) + ABIS)
    args = parser.parse_args()

    lock = json.loads(args.lock.read_text(encoding="utf-8"))
    selected = {}
    for pack in lock.get("packs", []):
        if int(pack.get("javaMajor", 0)) != args.major:
            continue
        if args.abi != "both" and pack.get("abi") != args.abi:
            continue
        if pack.get("abi") in ABIS:
            selected[pack["abi"]] = pack

    if len(selected) != (2 if args.abi == "both" else 1):
        print(f"error: lock file has no complete Java {args.major} pack set "
              f"for {args.abi}", file=sys.stderr)
        return 1

    clear_previous(args.dest)
    manifest = {"javaMajor": args.major, "abis": {}}
    for abi, pack in sorted(selected.items()):
        zip_path = args.packs / f"{pack['name']}.zip"
        if not zip_path.is_file():
            print(f"error: {zip_path} is missing — run "
                  f"scripts/fetch_bundled_jres.py first", file=sys.stderr)
            return 1
        natives = pack_natives(zip_path)
        if "libjvm.so" not in natives:
            print(f"error: {pack['name']} does not contain libjvm.so",
                  file=sys.stderr)
            return 1
        out_dir = args.dest / abi
        out_dir.mkdir(parents=True, exist_ok=True)
        total = 0
        for name in sorted(natives):
            (out_dir / name).write_bytes(natives[name])
            total += len(natives[name])
        manifest["abis"][abi] = sorted(natives)
        print(f"[bundle] {abi}: {len(natives)} libraries, "
              f"{total / (1024 * 1024):.1f} MB from {pack['name']}")

    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"JRE natives packaged into {args.dest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
