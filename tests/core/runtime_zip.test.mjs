/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  sanitizeRuntimeName,
  numberedRuntimeName,
  fileNameFromUri,
  releaseValue,
  majorFromVersion,
  javaMajorFromRelease,
  javaMajorFromFileName,
  abiFromOsArch,
  abiFromElfHeader
} from '../.build/core/runtime/RuntimeZipCore.ts';

const RELEASE_21 = [
  'IMPLEMENTOR="Eclipse Adoptium"',
  'JAVA_VERSION="21.0.5"',
  'JAVA_VERSION_DATE="2024-10-15"',
  'OS_ARCH="x86_64"',
  'OS_NAME="Linux"',
  ''
].join('\n');

test('sanitizeRuntimeName makes a safe directory name', () => {
  assert.equal(sanitizeRuntimeName('jdk-21+35.zip'), 'jdk-21+35');
  assert.equal(sanitizeRuntimeName('OpenJDK 21 (x86_64).zip'),
    'OpenJDK_21__x86_64');
  assert.equal(sanitizeRuntimeName('../etc/passwd.zip'), '_etc_passwd');
  assert.equal(sanitizeRuntimeName('.hidden.zip'), 'hidden');
  assert.equal(sanitizeRuntimeName('   '), 'imported-jdk');
  assert.equal(sanitizeRuntimeName('.zip'), 'imported-jdk');
  assert.equal(sanitizeRuntimeName('a'.repeat(90)).length, 60);
});

test('numberedRuntimeName suffixes the second and later imports', () => {
  assert.equal(numberedRuntimeName('jre21', 1), 'jre21');
  assert.equal(numberedRuntimeName('jre21', 2), 'jre21-2');
  assert.equal(numberedRuntimeName('jre21', 7), 'jre21-7');
});

test('fileNameFromUri decodes the last segment and ignores query/hash', () => {
  assert.equal(
    fileNameFromUri('file://docs/storage/Users/currentUser/Download/jdk%2021.zip'),
    'jdk 21.zip');
  assert.equal(fileNameFromUri('file://docs/a/b/jre21-ohos-x86_64.zip?x=1#y'),
    'jre21-ohos-x86_64.zip');
  assert.equal(fileNameFromUri('file://docs/a/b/'), 'b');
  assert.equal(fileNameFromUri('jdk21.zip'), 'jdk21.zip');
  assert.equal(fileNameFromUri('file://docs/bad%zz.zip'), 'bad%zz.zip');
});

test('releaseValue reads quoted and unquoted values', () => {
  assert.equal(releaseValue(RELEASE_21, 'JAVA_VERSION'), '21.0.5');
  assert.equal(releaseValue(RELEASE_21, 'OS_ARCH'), 'x86_64');
  assert.equal(releaseValue('OS_ARCH=x86_64\n', 'OS_ARCH'), 'x86_64');
  assert.equal(releaseValue('  JAVA_VERSION = "17"  \n', 'JAVA_VERSION'), '');
  assert.equal(releaseValue(RELEASE_21, 'MISSING'), '');
});

test('majorFromVersion handles modern and 1.x versions', () => {
  assert.equal(majorFromVersion('21.0.5'), 21);
  assert.equal(majorFromVersion('25'), 25);
  assert.equal(majorFromVersion('1.8.0_392'), 8);
  assert.equal(majorFromVersion('1.7.0'), 7);
  assert.equal(majorFromVersion('1.x'), 0);
  assert.equal(majorFromVersion('abc'), 0);
  assert.equal(majorFromVersion(''), 0);
  assert.equal(majorFromVersion('0.9'), 0);
});

test('javaMajorFromRelease reads JAVA_VERSION only', () => {
  assert.equal(javaMajorFromRelease(RELEASE_21), 21);
  assert.equal(javaMajorFromRelease('OS_ARCH="aarch64"\n'), 0);
  assert.equal(javaMajorFromRelease(''), 0);
});

test('javaMajorFromFileName falls back to the archive name', () => {
  assert.equal(javaMajorFromFileName('jre8-ohos-aarch64.zip'), 8);
  assert.equal(javaMajorFromFileName('jdk-21.0.5.zip'), 21);
  assert.equal(javaMajorFromFileName('OpenJDK17U-jre_x64.zip'), 17);
  assert.equal(javaMajorFromFileName('java8.zip'), 8);
  assert.equal(javaMajorFromFileName('zulu17.44-ca.zip'), 0);
  assert.equal(javaMajorFromFileName('runtime.zip'), 0);
});

test('abiFromOsArch maps release architectures', () => {
  assert.equal(abiFromOsArch(RELEASE_21), 'x86_64');
  assert.equal(abiFromOsArch('OS_ARCH="aarch64"\n'), 'arm64-v8a');
  assert.equal(abiFromOsArch('OS_ARCH="arm64"\n'), 'arm64-v8a');
  assert.equal(abiFromOsArch('OS_ARCH="amd64"\n'), 'x86_64');
  assert.equal(abiFromOsArch('OS_ARCH="riscv64"\n'), '');
  assert.equal(abiFromOsArch('JAVA_VERSION="21"\n'), '');
});

function elfHeader(machine, littleEndian = true, magic = 0x7f) {
  const bytes = new Uint8Array(20);
  bytes[0] = magic;
  bytes[1] = 0x45;
  bytes[2] = 0x4c;
  bytes[3] = 0x46;
  bytes[4] = 2;
  bytes[5] = littleEndian ? 1 : 2;
  if (littleEndian) {
    bytes[18] = machine & 0xff;
    bytes[19] = (machine >> 8) & 0xff;
  } else {
    bytes[18] = (machine >> 8) & 0xff;
    bytes[19] = machine & 0xff;
  }
  return bytes;
}

test('abiFromElfHeader maps e_machine in both endiannesses', () => {
  assert.equal(abiFromElfHeader(elfHeader(183)), 'arm64-v8a');
  assert.equal(abiFromElfHeader(elfHeader(62)), 'x86_64');
  assert.equal(abiFromElfHeader(elfHeader(183, false)), 'arm64-v8a');
  assert.equal(abiFromElfHeader(elfHeader(62, false)), 'x86_64');
});

test('abiFromElfHeader rejects non-ELF and short headers', () => {
  assert.equal(abiFromElfHeader(new Uint8Array(20)), '');
  assert.equal(abiFromElfHeader(elfHeader(62, true, 0x00)), '');
  assert.equal(abiFromElfHeader(new Uint8Array(4)), '');
  assert.equal(abiFromElfHeader(new Uint8Array(0)), '');
  assert.equal(abiFromElfHeader(elfHeader(3)), '');
});
