/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Imports a JDK/JRE from a user-picked .zip: copy out of the picker URI,
 * extract into the sandbox, validate libjvm and architecture, detect the
 * Java major version, then register the runtime.json marker used by
 * JavaRuntimeManager. The zip's own license terms apply to the imported JDK.
 */

import fs from '@ohos.file.fs';
import zlib from '@ohos.zlib';
import common from '@ohos.app.ability.common';
import { Paths } from '../common/Paths';
import { Logger } from '../common/Logger';
import {
  RuntimeDescriptor,
  JavaRuntimeManager
} from './JavaRuntimeManager';
import {
  abiFromElfHeader,
  abiFromOsArch,
  fileNameFromUri,
  javaMajorFromFileName,
  javaMajorFromRelease,
  numberedRuntimeName,
  sanitizeRuntimeName
} from '../core/runtime/RuntimeZipCore';

const TAG: string = 'RuntimeImporter';
const FAILED: string = 'JDK import failed: ';
const LIBJVM_CANDIDATES: Array<string> = [
  'lib/server/libjvm.so',
  'lib/aarch64/server/libjvm.so',
  'lib/x86_64/server/libjvm.so',
  'lib/arm64/server/libjvm.so'
];

export class RuntimeImporter {
  /**
   * Returns a human-readable result; never throws for expected failures
   * (bad zip, wrong ABI, missing libjvm). Partial extraction is removed.
   */
  public static async importZip(uri: string): Promise<string> {
    const originalName: string = fileNameFromUri(uri);
    const baseName: string = sanitizeRuntimeName(originalName);
    Paths.ensureDir(Paths.jvmDir());
    let name: string = baseName;
    let index: number = 1;
    while (fs.accessSync(Paths.jvmRuntimeDir(name)) ||
           fs.accessSync(`${Paths.jvmDir()}/${name}.zip`)) {
      index++;
      name = numberedRuntimeName(baseName, index);
      if (index > 50) {
        return FAILED + 'too many runtimes with this name';
      }
    }
    const zipPath: string = `${Paths.jvmDir()}/${name}.zip`;
    const destDir: string = Paths.jvmRuntimeDir(name);
    try {
      await RuntimeImporter.copyFromUri(uri, zipPath);
      const stat: fs.Stat = fs.statSync(zipPath);
      if (!stat.isFile() || stat.size === 0) {
        RuntimeImporter.removeTree(zipPath);
        return FAILED + 'the selected file is empty';
      }
      Paths.ensureDir(destDir);
      try {
        await zlib.decompressFile(zipPath, destDir);
      } catch (err) {
        RuntimeImporter.cleanup(destDir, zipPath);
        return FAILED + 'not a readable zip archive';
      }
      const homePath: string = JavaRuntimeManager.findJvmHome(destDir);
      if (homePath.length === 0) {
        RuntimeImporter.cleanup(destDir, zipPath);
        return FAILED + 'no libjvm.so found in the archive';
      }
      const release: string = RuntimeImporter.readRelease(homePath, destDir);
      const abi: string = RuntimeImporter.detectAbi(homePath, release);
      if (abi.length === 0) {
        RuntimeImporter.cleanup(destDir, zipPath);
        return FAILED + 'cannot determine the libjvm.so architecture';
      }
      const deviceAbi: string = Paths.deviceAbi();
      if (abi !== deviceAbi) {
        RuntimeImporter.cleanup(destDir, zipPath);
        return FAILED + `archive is ${abi}, this device is ${deviceAbi}`;
      }
      let major: number = javaMajorFromRelease(release);
      if (major === 0) {
        major = javaMajorFromFileName(originalName);
      }
      if (major === 0) {
        RuntimeImporter.cleanup(destDir, zipPath);
        return FAILED + 'cannot determine the Java version ' +
          '(no release file and no version in the file name)';
      }
      const descriptor: RuntimeDescriptor = {
        name: name,
        javaMajor: major,
        abi: abi,
        homePath: homePath
      };
      Paths.writeTextFileSync(`${destDir}/runtime.json`,
        JSON.stringify(descriptor));
      RuntimeImporter.removeTree(zipPath);
      Logger.info(TAG, `imported ${name} Java ${major} ${abi}`);
      return `Imported ${name} (Java ${major}, ${abi}).`;
    } catch (err) {
      const message: string = (err as Error).message;
      RuntimeImporter.cleanup(destDir, zipPath);
      Logger.error(TAG, `import failed: ${message}`);
      return FAILED + message;
    }
  }

  private static async copyFromUri(uri: string, destZip: string): Promise<void> {
    const source: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const dest: fs.File = fs.openSync(destZip,
      fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      await fs.copyFile(source.fd, dest.fd);
    } finally {
      fs.closeSync(source);
      fs.closeSync(dest);
    }
  }

  private static readRelease(homePath: string, destDir: string): string {
    const candidates: Array<string> = [`${homePath}/release`,
      `${destDir}/release`];
    for (let i = 0; i < candidates.length; i++) {
      if (fs.accessSync(candidates[i])) {
        try {
          return fs.readTextSync(candidates[i]);
        } catch (err) {
          Logger.warn(TAG, `cannot read ${candidates[i]}`);
        }
      }
    }
    return '';
  }

  private static detectAbi(homePath: string, release: string): string {
    const fromRelease: string = abiFromOsArch(release);
    if (fromRelease.length > 0) {
      return fromRelease;
    }
    for (let i = 0; i < LIBJVM_CANDIDATES.length; i++) {
      const path: string = `${homePath}/${LIBJVM_CANDIDATES[i]}`;
      if (!fs.accessSync(path)) {
        continue;
      }
      try {
        const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
        try {
          const buffer: ArrayBuffer = new ArrayBuffer(20);
          const read: number = fs.readSync(file.fd, buffer);
          return abiFromElfHeader(new Uint8Array(buffer, 0, read));
        } finally {
          fs.closeSync(file);
        }
      } catch (err) {
        Logger.warn(TAG, `cannot read ${path}`);
      }
    }
    return '';
  }

  private static cleanup(destDir: string, zipPath: string): void {
    try {
      RuntimeImporter.removeTree(destDir);
    } catch (err) {
      // best effort
    }
    try {
      RuntimeImporter.removeTree(zipPath);
    } catch (err) {
      // best effort
    }
  }

  private static removeTree(real: string): void {
    if (!fs.accessSync(real)) {
      return;
    }
    if (fs.statSync(real).isDirectory()) {
      const names: Array<string> = fs.listFileSync(real);
      for (let i = 0; i < names.length; i++) {
        RuntimeImporter.removeTree(`${real}/${names[i]}`);
      }
      fs.rmdirSync(real);
    } else {
      fs.unlinkSync(real);
    }
  }
}
