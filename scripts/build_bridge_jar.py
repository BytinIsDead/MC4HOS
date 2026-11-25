#!/usr/bin/env python3
# Copyright (C) 2026 MC4HOS Contributors
# SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

"""Builds mc4hos-bridge.jar from entry/src/main/cpp/java.

The jar is packaged at resources/rawfile/bridge/mc4hos-bridge.jar so the
HAP ships the Java side of the bridge (docs/NATIVES.md §3). DeployImport
stages it into <sandbox>/bridge/ atomically and refreshes stale versions.
"""

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT: Path = Path(__file__).resolve().parent.parent
SRC: Path = ROOT / 'entry' / 'src' / 'main' / 'cpp' / 'java'
OUT: Path = (ROOT / 'entry' / 'src' / 'main' / 'resources'
             / 'rawfile' / 'bridge' / 'mc4hos-bridge.jar')


def tool(name: str) -> str:
    found: str | None = shutil.which(name)
    if found is not None:
        return found
    home: str | None = os.environ.get('JAVA_HOME')
    if home is not None:
        suffix: str = '.exe' if os.name == 'nt' else ''
        candidate = Path(home) / 'bin' / (name + suffix)
        if candidate.exists():
            return str(candidate)
    sys.exit(f'error: {name} not found — install a JDK or set JAVA_HOME')


def main() -> int:
    sources: list[str] = sorted(str(p) for p in SRC.rglob('*.java'))
    if not sources:
        print(f'error: no Java sources under {SRC}', file=sys.stderr)
        return 1
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as classes:
        subprocess.run(
            [tool('javac'), '-source', '8', '-target', '8',
             '-encoding', 'UTF-8', '-d', classes, *sources],
            check=True)
        subprocess.run(
            [tool('jar'), 'cf', str(OUT), '-C', classes, '.'], check=True)
    print(f'bridge jar: {OUT} ({OUT.stat().st_size} bytes, '
          f'{len(sources)} sources)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
