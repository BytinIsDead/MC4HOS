#!/usr/bin/env python3
# Copyright (C) 2026 MC4HOS Contributors
# SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

"""Encodes the sync/build configuration rules that broke hvigor in practice.

Checks (each maps to a real failure mode — see docs/BUILD.md §2):
  1. resources/**/*.json and profile/*.json are STRICT JSON (restool 11203002)
  2. no '#' comments in any .json5 (hvigor parser rejects them)
  3. modelVersion is identical in oh-package.json5 and both hvigor configs
  4. HarmonyOS SDK strings keep the "(api)" suffix and compatible <= target
  5. AppScope/app.json5 declares buildVersion (6.x schema requirement)
  6. app icons are real PNG files (SVG is rejected for app icons)
"""

import json
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
SKIP_DIRS = {".git", "node_modules", "oh_modules", ".cxx", ".idea", "build",
             ".hvigor"}
errors = []


def fail(msg: str) -> None:
    errors.append(msg)


# 1. strict-JSON resource files
resource_files = sorted(
    list(root.glob("AppScope/resources/**/*.json"))
    + list(root.glob("entry/src/main/resources/**/*.json"))
)
for p in resource_files:
    text = p.read_text(encoding="utf-8")
    try:
        json.loads(text)
    except json.JSONDecodeError as e:
        fail(f"{p.relative_to(root)}: not strict JSON ({e.msg} at line {e.lineno})")

# 2. '#' comments anywhere in .json5 configs
for p in sorted(root.rglob("*.json5")):
    if set(p.relative_to(root).parts) & SKIP_DIRS:
        continue
    for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
        if line.lstrip().startswith("#"):
            fail(f"{p.relative_to(root)}:{i}: '#' comment (JSON5 allows // only)")

# 3. modelVersion consistency
def model_version(path: pathlib.Path):
    if not path.exists():
        return None
    m = re.search(r'"modelVersion":\s*"([^"]+)"',
                  path.read_text(encoding="utf-8"))
    return m.group(1) if m else None


versions = {
    "oh-package.json5": model_version(root / "oh-package.json5"),
    "hvigor/hvigor-config.json5": model_version(root / "hvigor" / "hvigor-config.json5"),
    ".hvigor/hvigor-config.json5": model_version(root / ".hvigor" / "hvigor-config.json5"),
}
declared = {k: v for k, v in versions.items() if v is not None}
if not declared:
    fail("no modelVersion found in oh-package.json5 / hvigor configs")
elif len(set(declared.values())) > 1:
    fail(f"modelVersion mismatch across configs: {declared}")
else:
    print(f"modelVersion: {next(iter(declared.values()))} (consistent)")

# 4. SDK version strings
bp = (root / "build-profile.json5").read_text(encoding="utf-8")
sdk = {}
for key in ("compatibleSdkVersion", "targetSdkVersion"):
    m = re.search(rf'"{key}":\s*"([^"]+)"', bp)
    if not m:
        fail(f"build-profile.json5: {key} missing")
        continue
    value = m.group(1)
    match = re.fullmatch(r"(\d+\.\d+\.\d+)\((\d+)\)", value)
    if not match:
        fail(f'build-profile.json5: {key}="{value}" lacks the "(api)" suffix '
             f'(HarmonyOS requires e.g. "6.1.1(24)")')
        continue
    sdk[key] = int(match.group(2))
if "compatibleSdkVersion" in sdk and "targetSdkVersion" in sdk:
    if sdk["targetSdkVersion"] < sdk["compatibleSdkVersion"]:
        fail("build-profile.json5: targetSdkVersion < compatibleSdkVersion "
             "(ordering rule violated)")

# 5. buildVersion
app = (root / "AppScope" / "app.json5").read_text(encoding="utf-8")
if '"buildVersion"' not in app:
    fail("AppScope/app.json5: missing required 'buildVersion' (6.x schema)")

# 6. PNG app icons
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
for media in (root / "AppScope/resources/base/media",
              root / "entry/src/main/resources/base/media"):
    icon = media / "app_icon.png"
    if not icon.exists():
        fail(f"{icon.relative_to(root)}: missing (app icons must be PNG)")
    elif not icon.read_bytes().startswith(PNG_MAGIC):
        fail(f"{icon.relative_to(root)}: not a PNG file")

if errors:
    print(f"FAIL: {len(errors)} config rule violation(s):")
    for e in errors:
        print("  -", e)
    return_code = 1
else:
    print(f"OK: {len(resource_files)} strict-JSON resources valid; "
          "all config rules satisfied")
    return_code = 0
sys.exit(return_code)
