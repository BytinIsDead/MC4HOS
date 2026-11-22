/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Pure helpers for importing a user-picked JDK/JRE zip. No HarmonyOS
 * imports, so this file is exercised by the Node tests.
 */

/** Stable directory/file name derived from a user-supplied zip name. */
export function sanitizeRuntimeName(raw: string): string {
  let base: string = raw.trim();
  if (base.toLowerCase().endsWith('.zip')) {
    base = base.substring(0, base.length - 4);
  }
  let out: string = '';
  for (let i = 0; i < base.length; i++) {
    const c: string = base.charAt(i);
    const letter: boolean =
      (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
    const digit: boolean = c >= '0' && c <= '9';
    if (letter || digit || c === '.' || c === '_' || c === '-' ||
        c === '+') {
      out += c;
    } else {
      out += '_';
    }
  }
  while (out.startsWith('.')) {
    out = out.substring(1);
  }
  while (out.length > 0 && '. _-+'.indexOf(out.charAt(out.length - 1)) >= 0) {
    out = out.substring(0, out.length - 1);
  }
  if (out.length > 60) {
    out = out.substring(0, 60);
  }
  if (out.length === 0 || out === '.' || out === '..') {
    return 'imported-jdk';
  }
  return out;
}

/** `base` for the first import, `base-2`, `base-3`… afterwards. */
export function numberedRuntimeName(base: string, index: number): string {
  return index <= 1 ? base : `${base}-${index}`;
}

/** Last path segment of a picker URI, percent-decoded. */
export function fileNameFromUri(uri: string): string {
  let path: string = uri.trim();
  const query: number = path.indexOf('?');
  if (query >= 0) {
    path = path.substring(0, query);
  }
  const hash: number = path.indexOf('#');
  if (hash >= 0) {
    path = path.substring(0, hash);
  }
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  const slash: number = path.lastIndexOf('/');
  const name: string = slash >= 0 ? path.substring(slash + 1) : path;
  try {
    return decodeURIComponent(name);
  } catch (err) {
    return name;
  }
}

/** Reads `KEY="value"` from a JDK `release` file. */
export function releaseValue(releaseText: string, key: string): string {
  const lines: Array<string> = releaseText.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line: string = lines[i].trim();
    if (!line.startsWith(`${key}=`)) {
      continue;
    }
    let value: string = line.substring(key.length + 1).trim();
    if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
      value = value.substring(1, value.length - 1);
    }
    return value;
  }
  return '';
}

/** "21.0.5" -> 21, "1.8.0_392" -> 8, "" -> 0. */
export function majorFromVersion(version: string): number {
  const parts: Array<string> = version.trim().split('.');
  if (parts.length === 0) {
    return 0;
  }
  const first: number = Number(parts[0]);
  if (!Number.isInteger(first) || first <= 0) {
    return 0;
  }
  if (first === 1 && parts.length > 1) {
    const second: number = Number(parts[1]);
    return Number.isInteger(second) && second > 0 ? second : 0;
  }
  return first;
}

export function javaMajorFromRelease(releaseText: string): number {
  return majorFromVersion(releaseValue(releaseText, 'JAVA_VERSION'));
}

/** Fallback for archives without a release file: jdk-21, jre8, zulu17… */
export function javaMajorFromFileName(name: string): number {
  const named: RegExpExecArray | null =
    /(?:jre|jdk|java)[-_ ]?(\d+)/i.exec(name);
  if (named !== null) {
    return Number(named[1]);
  }
  const dashed: RegExpExecArray | null = /[-_](\d+)(?:[._-]|$)/.exec(name);
  if (dashed !== null) {
    return Number(dashed[1]);
  }
  return 0;
}

/** OS_ARCH from a release file mapped to the app's ABI spelling. */
export function abiFromOsArch(releaseText: string): string {
  const arch: string = releaseValue(releaseText, 'OS_ARCH').toLowerCase();
  if (arch === 'aarch64' || arch === 'arm64' || arch === 'arm64-v8a') {
    return 'arm64-v8a';
  }
  if (arch === 'x86_64' || arch === 'amd64' || arch === 'x64') {
    return 'x86_64';
  }
  return '';
}

/** e_machine from an ELF header, mapped to the app's ABI spelling. */
export function abiFromElfHeader(bytes: Uint8Array): string {
  if (bytes.length < 20 || bytes[0] !== 0x7f || bytes[1] !== 0x45 ||
      bytes[2] !== 0x4c || bytes[3] !== 0x46) {
    return '';
  }
  const littleEndian: boolean = bytes[5] !== 2;
  let machine: number = 0;
  if (littleEndian) {
    machine = bytes[18] | (bytes[19] << 8);
  } else {
    machine = (bytes[18] << 8) | bytes[19];
  }
  if (machine === 183) {
    return 'arm64-v8a';
  }
  if (machine === 62) {
    return 'x86_64';
  }
  return '';
}
