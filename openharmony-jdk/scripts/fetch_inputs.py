#!/usr/bin/env python3
# Copyright (C) 2026 MC4HOS Contributors
# SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

"""Downloads and verifies a pinned OpenJDK-OHOS build-input archive.

The archive is third-party GPLv2+CE material (patches and stubs) and is never
committed to this repository. Its SHA-256 and size are pinned in
openharmony-jdk/build-inputs.lock.json.
"""

import argparse
import hashlib
import json
import pathlib
import sys
import urllib.request
import zipfile

HERE = pathlib.Path(__file__).resolve().parent
LOCK = HERE.parent / "build-inputs.lock.json"
CHUNK = 1024 * 1024
MARKER = ".inputs-sha256"


def sha256_of(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(CHUNK), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(url: str, dest: pathlib.Path, expected_size: int) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_suffix(dest.suffix + ".part")
    if part.exists():
        part.unlink()
    received = 0
    with urllib.request.urlopen(url, timeout=60) as resp, part.open("wb") as out:
        while True:
            chunk = resp.read(CHUNK)
            if not chunk:
                break
            out.write(chunk)
            received += len(chunk)
            if expected_size > 0:
                pct = min(100, received * 100 // expected_size)
                print(f"\r  {received}/{expected_size} bytes ({pct}%)",
                      end="", flush=True)
    print("")
    if expected_size > 0 and received != expected_size:
        part.unlink()
        raise RuntimeError(
            f"size mismatch: expected {expected_size}, got {received}")
    part.replace(dest)


def extract_checked(archive: pathlib.Path, dest: pathlib.Path) -> None:
    root = dest.resolve()
    with zipfile.ZipFile(archive) as zf:
        for info in zf.infolist():
            target = (root / info.filename).resolve()
            if not target.is_relative_to(root):
                raise RuntimeError(f"unsafe zip member: {info.filename}")
        zf.extractall(root)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--major", required=True, choices=["21", "25"])
    parser.add_argument("--dest", required=True, type=pathlib.Path)
    parser.add_argument("--lock", type=pathlib.Path, default=LOCK)
    args = parser.parse_args()

    lock = json.loads(args.lock.read_text(encoding="utf-8"))
    item = lock["runtimes"][args.major]
    dest = args.dest.resolve()
    marker = dest / MARKER
    series = dest / "prebuilt" / "jdk" / args.major / "patches" / "series"
    if marker.is_file() and series.is_file():
        if marker.read_text(encoding="utf-8").strip() == item["sha256"]:
            print(f"Using verified build inputs already at {dest}")
            return 0
        raise RuntimeError(
            f"{dest} contains different inputs; use a new --dest directory")

    if dest.exists():
        raise RuntimeError(
            f"{dest} exists without a verified marker; use a new --dest directory")
    dest.mkdir(parents=True)

    archive = dest.parent / item["asset"]
    print(f"Downloading {item['url']}")
    download(item["url"], archive, int(item.get("sizeBytes", 0)))
    actual = sha256_of(archive)
    if actual != item["sha256"]:
        archive.unlink()
        raise RuntimeError(
            f"sha256 mismatch: expected {item['sha256']}, got {actual}")
    print(f"sha256 OK: {actual}")

    extract_checked(archive, dest)
    archive.unlink()
    if not series.is_file():
        raise RuntimeError(f"archive did not contain {series.relative_to(dest)}")
    marker.write_text(item["sha256"] + "\n", encoding="utf-8")
    print(f"Verified build inputs at {dest}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # surfaced verbatim in CI logs
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)
