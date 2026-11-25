#!/usr/bin/env python3
# Copyright (C) 2026 MC4HOS Contributors
# SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

import argparse
import io
import struct
import sys
import zipfile
from pathlib import Path

REQUIRED_LIBRARIES = (
    "libjvm.so",
    "liblwjgl_343.so",
    "liblwjgl_343_opengl.so",
    "liblwjgl_343_stb.so",
    "liblwjgl_tinyfd.so",
    "libopenal.so",
    "libfreetype.so",
)
ELF_MACHINES = {"arm64-v8a": 183, "x86_64": 62}


def validate_elf(data: bytes, label: str, abi: str, errors: list[str]) -> None:
    if len(data) < 64 or data[:4] != b"\x7fELF":
        errors.append(f"truncated or not an ELF file: {label}")
        return
    elf_type, machine, version = struct.unpack_from("<HHI", data, 16)
    header_size = struct.unpack_from("<H", data, 52)[0]
    if data[4] != 2 or data[5] != 1:
        errors.append(f"not a little-endian ELF64 file: {label}")
    elif elf_type != 3 or machine != ELF_MACHINES[abi] or version != 1 or header_size != 64:
        errors.append(f"invalid ELF shared-object header for {abi}: {label}")


def validate_jar(data: bytes, label: str, errors: list[str]) -> None:
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            names = set(archive.namelist())
            for name in (
                "org/lwjgl/glfw/GLFW.class",
                "org/lwjgl/system/MeowBundledNameMapper.class",
            ):
                if name not in names:
                    errors.append(f"adapted LWJGL class missing from {label}: {name}")
            if b"meowcraftbridge" not in archive.read("org/lwjgl/glfw/GLFW.class"):
                errors.append(f"stock GLFW provider detected in {label}")
    except (OSError, zipfile.BadZipFile, KeyError) as exc:
        errors.append(f"invalid LWJGL JAR {label}: {exc}")


def validate_bridge_jar(data: bytes, label: str, errors: list[str]) -> None:
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            names = set(archive.namelist())
            for name in (
                "org/mc4hos/bridge/InputBridge.class",
                "org/mc4hos/bridge/PlatformBridge.class",
                "org/mc4hos/bridge/SelfTest.class",
            ):
                if name not in names:
                    errors.append(f"MC4HOS bridge class missing from {label}: {name}")
    except (OSError, zipfile.BadZipFile) as exc:
        errors.append(f"invalid MC4HOS bridge JAR {label}: {exc}")


def validate_hap(path: Path, errors: list[str]) -> None:
    try:
        with zipfile.ZipFile(path) as archive:
            infos = archive.infolist()
            counts = {}
            for info in infos:
                counts[info.filename] = counts.get(info.filename, 0) + 1
            required = list(REQUIRED_LIBRARIES) + ["libmc4hos_core.so", "libmeowcraftbridge.so"]
            for abi in ELF_MACHINES:
                for name in required:
                    entry = f"libs/{abi}/{name}"
                    if counts.get(entry, 0) == 0:
                        errors.append(f"HAP entry missing: {path}!/{entry}")
                    elif counts[entry] > 1:
                        errors.append(f"HAP entry duplicated: {path}!/{entry}")
                    else:
                        validate_elf(archive.read(entry), f"{path}!/{entry}", abi, errors)
            for name in ("mc4hos-bridge.jar", "lwjgl-3.4.3.jar"):
                entry = f"resources/rawfile/bridge/{name}"
                if counts.get(entry, 0) != 1:
                    errors.append(f"HAP bridge JAR missing or duplicated: {path}!/{entry}")
            validate_jar(
                archive.read("resources/rawfile/bridge/lwjgl-3.4.3.jar"),
                f"{path}!/resources/rawfile/bridge/lwjgl-3.4.3.jar",
                errors,
            )
            validate_bridge_jar(
                archive.read("resources/rawfile/bridge/mc4hos-bridge.jar"),
                f"{path}!/resources/rawfile/bridge/mc4hos-bridge.jar",
                errors,
            )
    except (OSError, zipfile.BadZipFile, KeyError) as exc:
        errors.append(f"invalid HAP {path}: {exc}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify staged or packaged MC4HOS game natives")
    parser.add_argument("--entry", type=Path, default=Path(__file__).resolve().parents[1] / "entry")
    parser.add_argument("--hap", type=Path, help="validate a built HAP instead of staged inputs")
    args = parser.parse_args()
    errors = []

    if args.hap is not None:
        validate_hap(args.hap.resolve(), errors)
    else:
        entry = args.entry.resolve()
        for abi in ELF_MACHINES:
            for name in REQUIRED_LIBRARIES:
                path = entry / "libs" / abi / name
                if not path.is_file() or path.stat().st_size < 64:
                    errors.append(f"missing, empty, or truncated: {path}")
                    continue
                with path.open("rb") as stream:
                    header = stream.read(64)
                validate_elf(header, str(path), abi, errors)

        jar = entry / "src/main/resources/rawfile/bridge/lwjgl-3.4.3.jar"
        if not jar.is_file() or jar.stat().st_size == 0:
            errors.append(f"missing or empty: {jar}")
        else:
            validate_jar(jar.read_bytes(), str(jar), errors)

        bridge_jar = entry / "src/main/resources/rawfile/bridge/mc4hos-bridge.jar"
        if not bridge_jar.is_file() or bridge_jar.stat().st_size == 0:
            errors.append(f"missing or empty: {bridge_jar}")
        else:
            validate_bridge_jar(bridge_jar.read_bytes(), str(bridge_jar), errors)

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        if args.hap is None:
            print(
                "Build the pinned stack with scripts/native/build_stack.sh, package "
                "Java 21 natives with scripts/bundle_jre_natives.py, and compile the "
                "bridge with scripts/build_bridge_jar.py.",
                file=sys.stderr,
            )
        return 1

    if args.hap is not None:
        print(f"OK: {args.hap} contains both ABIs, the native stack, and both bridge JARs")
    else:
        print("OK: Java 21 and game native inputs are present for arm64-v8a and x86_64")
        print("OK: adapted LWJGL 3.4.3 and MC4HOS bridge JARs contain their required classes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
