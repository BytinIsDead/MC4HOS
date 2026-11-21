#!/usr/bin/env python3
# Copyright (C) 2026 MC4HOS Contributors
# SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

"""Writes the runtime-catalog entry for a packaged x86_64 runtime zip."""

import argparse
import hashlib
import json
import pathlib


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--major", required=True, choices=["21", "25"])
    parser.add_argument("--zip", required=True, type=pathlib.Path)
    parser.add_argument("--out", required=True, type=pathlib.Path)
    parser.add_argument("--url", default="")
    args = parser.parse_args()

    data = args.zip.read_bytes()
    entry = {
        "name": f"jre{args.major}-ohos-x86_64",
        "javaMajor": int(args.major),
        "abi": "x86_64",
        "packUrl": args.url,
        "sha256": hashlib.sha256(data).hexdigest(),
        "sizeBytes": len(data),
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps([entry], indent=2) + "\n", encoding="utf-8")
    (args.out.parent / f"jre{args.major}-ohos-x86_64.sha256").write_text(
        f"{entry['sha256']}  {args.zip.name}\n", encoding="utf-8")
    print(json.dumps(entry, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
