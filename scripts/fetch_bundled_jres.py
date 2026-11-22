#!/usr/bin/env python3
# Copyright (C) 2026 MC4HOS Contributors
# SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

"""Fetches runtime packs into the HAP rawfile directory.

The packs are third-party binaries (OpenJDK GPLv2+CE builds) and are never
committed: this script downloads them at build time into
entry/src/main/resources/rawfile/jvm/ so hvigor packages them inside the HAP.
The app extracts the pack matching the device ABI and required Java major on
first use.

aarch64 packs are pinned by size and SHA-256. x86_64 packs come from the
separate openharmony-openjdk repository's jdk-ohos-v1 release and are pinned
the same way; the release catalog is consulted for any entry that lacks a
digest, and entries marked optional are skipped when unavailable.

After fetching, the script writes OpenJDK-LICENSE.txt (GPLv2 + Classpath
Exception) and RUNTIME-NOTICES.txt with each pack's source identity into the
destination, so the HAP redistributes the runtime together with its license.
"""

import argparse
import hashlib
import json
import pathlib
import shutil
import sys
import urllib.error
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
LOCK = HERE / "bundled-jres.lock.json"
DEFAULT_DEST = ROOT / "entry/src/main/resources/rawfile/jvm"
OPENJDK_LICENSE = HERE / "licenses" / "OpenJDK-LICENSE.txt"
CHUNK = 1024 * 1024


def write_notices(dest: pathlib.Path, bundled: list) -> None:
    """Writes the OpenJDK license and a per-pack source notice next to the zips.

    Modern community runtime packs ship without the upstream license files, so
    the HAP distributes them itself. The notice names each pack's pinned source
    identity and the corresponding-source offer required by GPLv2 §3.
    """
    if OPENJDK_LICENSE.is_file():
        shutil.copyfile(OPENJDK_LICENSE, dest / "OpenJDK-LICENSE.txt")
    lines = [
        "Bundled OpenJDK runtime notices",
        "===============================",
        "",
        "This build bundles the following OpenJDK runtime packs. OpenJDK is",
        "Copyright (c) Oracle and/or its affiliates and is licensed under the GNU",
        "General Public License version 2 with the Classpath Exception. The full",
        "license text (GPLv2 plus the Classpath Exception appendix) accompanies",
        "this file as OpenJDK-LICENSE.txt. The JDK8 pack also keeps its upstream",
        "jre/LICENSE and jre/ASSEMBLY_EXCEPTION files inside the zip.",
        "",
        "Packs in this build:",
    ]
    for entry in bundled:
        lines.append("")
        lines.append(f"  {entry['name']}.zip  (Java {entry['javaMajor']}, {entry['abi']})")
        lines.append(f"    source:  {entry['url']}")
        lines.append(f"    sha256:  {entry['sha256']}")
        lines.append(f"    size:    {entry['size']} bytes")
    lines += [
        "",
        "Corresponding source (GPLv2 section 3):",
        "",
        "  aarch64 packs come unmodified from the pinned community releases named",
        "  above; use the source identities those releases publish, or request the",
        "  corresponding source from whoever distributed this application.",
        "",
        "  x86_64 packs are built by the openharmony-openjdk repository; the exact",
        "  upstream repositories, commits and build-input archives are recorded in",
        "  each pack's MC4HOS-RUNTIME-NOTICE.txt, in that repository's",
        "  build-inputs.lock.json, and in the jdk-ohos-v1 release.",
        "",
        "  You may also obtain the corresponding source from whoever gave you this",
        "  application, per GPLv2 section 3.",
        "",
    ]
    (dest / "RUNTIME-NOTICES.txt").write_text("\n".join(lines), encoding="utf-8")


def sha256_of(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(CHUNK), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(url: str, dest: pathlib.Path, expected_size: int) -> None:
    part = dest.with_suffix(dest.suffix + ".part")
    if part.exists():
        part.unlink()
    received = 0
    request = urllib.request.Request(url, headers={"User-Agent": "MC4HOS-bundler"})
    with urllib.request.urlopen(request, timeout=60) as resp, part.open("wb") as out:
        while True:
            chunk = resp.read(CHUNK)
            if not chunk:
                break
            out.write(chunk)
            received += len(chunk)
            if expected_size > 0:
                pct = min(100, received * 100 // expected_size)
                print(f"\r  {dest.name}: {received}/{expected_size} ({pct}%)",
                      end="", flush=True)
    print("")
    if expected_size > 0 and received != expected_size:
        part.unlink()
        raise RuntimeError(
            f"{dest.name}: size mismatch, expected {expected_size}, got {received}")
    part.replace(dest)


def verified(path: pathlib.Path, sha256: str, size: int) -> bool:
    if not path.is_file():
        return False
    if size > 0 and path.stat().st_size != size:
        return False
    if sha256:
        return sha256_of(path) == sha256
    return True


def load_release_catalog(url: str) -> dict:
    """Returns {name: entry} from the x86_64 release catalog, or {}."""
    if not url:
        return {}
    try:
        request = urllib.request.Request(
            url, headers={"User-Agent": "MC4HOS-bundler", "Accept": "application/json"})
        with urllib.request.urlopen(request, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, ValueError, OSError):
        return {}
    out = {}
    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict) and isinstance(item.get("name"), str):
                out[item["name"]] = item
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dest", type=pathlib.Path, default=DEFAULT_DEST)
    parser.add_argument("--lock", type=pathlib.Path, default=LOCK)
    parser.add_argument("--abi", default="both",
                        choices=["both", "arm64-v8a", "x86_64"])
    parser.add_argument("--major", default="",
                        help="comma-separated Java majors to fetch (default: all)")
    parser.add_argument("--require-all", action="store_true",
                        help="fail when an optional x86_64 pack is unavailable")
    args = parser.parse_args()

    lock = json.loads(args.lock.read_text(encoding="utf-8"))
    packs = lock.get("packs", [])
    majors = {int(m) for m in args.major.split(",") if m.strip()} if args.major else set()

    selected = []
    for pack in packs:
        if args.abi != "both" and pack.get("abi") != args.abi:
            continue
        if majors and int(pack.get("javaMajor", 0)) not in majors:
            continue
        selected.append(pack)
    if not selected:
        print("error: no packs match the requested ABI/major filter")
        return 1

    catalog = {}
    if any(not p.get("sha256") for p in selected):
        catalog = load_release_catalog(lock.get("x86CatalogUrl", ""))

    args.dest.mkdir(parents=True, exist_ok=True)
    failures = []
    skipped = []
    bundled = []

    for pack in selected:
        name = pack["name"]
        major = int(pack["javaMajor"])
        url = pack["url"]
        sha256 = (pack.get("sha256") or "").lower()
        size = int(pack.get("sizeBytes") or 0)
        optional = bool(pack.get("optional")) and not args.require_all

        if not sha256 and name in catalog:
            sha256 = str(catalog[name].get("sha256", "")).lower()
            size = int(catalog[name].get("sizeBytes") or size)

        dest = args.dest / f"{name}.zip"
        if verified(dest, sha256, size):
            print(f"[skip] {name}.zip already present and verified")
            bundled.append({"name": name, "javaMajor": major, "abi": pack.get("abi"),
                            "url": url, "sha256": sha256_of(dest),
                            "size": dest.stat().st_size})
            continue

        if dest.exists():
            dest.unlink()
        print(f"[fetch] {name}.zip (Java {major}, {pack.get('abi')})")
        try:
            download(url, dest, size)
            if sha256 and sha256_of(dest) != sha256:
                dest.unlink()
                raise RuntimeError("SHA-256 mismatch")
            if not sha256:
                print("  warning: no pinned digest for this pack")
            bundled.append({"name": name, "javaMajor": major, "abi": pack.get("abi"),
                            "url": url, "sha256": sha256_of(dest),
                            "size": dest.stat().st_size})
        except (urllib.error.URLError, urllib.error.HTTPError, OSError,
                RuntimeError) as err:
            if dest.exists():
                dest.unlink()
            if optional:
                print(f"  [optional] unavailable ({err}); skipping")
                skipped.append(name)
            else:
                print(f"  ERROR: {err}")
                failures.append(name)

    if bundled:
        write_notices(args.dest, bundled)

    print("")
    print(f"Bundled runtime directory: {args.dest}")
    if skipped:
        print("Skipped optional packs: " + ", ".join(skipped))
    if failures:
        print("FAILED: " + ", ".join(failures))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
