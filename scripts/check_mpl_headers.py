#!/usr/bin/env python3
# Copyright (C) 2026 MC4HOS Contributors
# SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

"""Verifies that every source file carries the project SPDX identifier.

Exemptions follow NOTICE.md: strict-JSON resource files (no comments
allowed) and machine-generated output directories are not checked; LICENSE
is the license itself.
"""

import pathlib
import sys

REQUIRED = "SPDX-License-Identifier: MPL-2.0-no-copyleft-exception"
SKIP_DIRS = {".git", "node_modules", "oh_modules", ".cxx", ".idea", "build",
             ".hvigor", ".preview", ".zcode", "rawfile", ".build", ".tmp",
             "out", "dist"}
EXTS = {".ets", ".ts", ".mjs", ".cpp", ".h", ".java", ".json5", ".md", ".txt",
        ".py", ".yml", ".yaml"}
NAMED = {"CMakeLists.txt"}
EXEMPT = {"LICENSE", "oh-package-lock.json5", "entry/oh-package-lock.json5",
          "entry/src/main/cpp/meowcraftbridge/jni.h",
          "entry/src/main/cpp/meowcraftbridge/jni_md.h",
          "scripts/native/lwjgl/pack_jar.py"}
# Verbatim third-party license texts shipped for redistribution compliance.
EXEMPT_DIRS = {("scripts", "licenses"),
               ("scripts", "native", "lwjgl", "overlay"),
               ("scripts", "native", "lwjgl", "overlay-3.4.3")}
# Lock files are ohpm-generated; also match any *-lock.json5 by suffix.
LOCK_SUFFIX = "-lock.json5"


def main() -> int:
    root = pathlib.Path(__file__).resolve().parent.parent
    missing = []
    checked = 0
    for p in sorted(root.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(root)
        if rel.as_posix() in EXEMPT or p.name.endswith(LOCK_SUFFIX):
            continue
        if rel.parent.parts in EXEMPT_DIRS:
            continue
        if set(rel.parts) & SKIP_DIRS:
            continue
        if p.suffix.lower() not in EXTS and p.name not in NAMED:
            continue
        checked += 1
        if REQUIRED not in p.read_text(encoding="utf-8", errors="replace"):
            missing.append(str(p.relative_to(root)))

    if missing:
        print(f"FAIL: {len(missing)} file(s) missing the required SPDX header:")
        for m in missing:
            print("  -", m)
        print(f"\nExpected: {REQUIRED}")
        print("Exempt (per NOTICE.md): strict-JSON resources, generated dirs, LICENSE.")
        return 1
    print(f"OK: {checked} source files carry {REQUIRED}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
