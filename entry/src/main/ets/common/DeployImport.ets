/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import fs from '@ohos.file.fs';
import zlib from '@ohos.zlib';
import { Paths } from './Paths';
import { RuntimeDescriptor, JavaRuntimeManager } from '../download/JavaRuntimeManager';
import { LWJGL_JAR_NAME, LWJGL_GENERATION } from '../launch/LaunchConfig';

/**
 * In-app deployment importer.
 *
 * `hdc file send` into an app sandbox often fails with "No such file or
 * directory" / permission errors — but /data/local/tmp is world-writable,
 * so the reliable flow is:
 *
 *   hdc file send jre21-ohos-x86_64.zip /data/local/tmp/
 *
 * …then import the runtime from the Settings page. Bridge JARs and game
 * natives are HAP components and are not sandbox imports.
 */

const TMP_DIR: string = '/data/local/tmp';

export class DeployImport {

  public static tmpPath(name: string): string {
    return `${TMP_DIR}/${name}`;
  }

  public static async hasTmp(name: string): Promise<boolean> {
    try {
      return fs.accessSync(DeployImport.tmpPath(name));
    } catch (err) {
      return false;
    }
  }

  /** Lists /data/local/tmp so the user can see what is ready to import. */
  public static async listTmp(): Promise<string> {
    try {
      const names: Array<string> = fs.listFileSync(TMP_DIR);
      if (names.length === 0) {
        return `${TMP_DIR} is empty`;
      }
      return `${TMP_DIR}:\n` + names.join('\n');
    } catch (err) {
      const e = err as Error;
      return `Cannot list ${TMP_DIR}: ${e.message}`;
    }
  }

  private static async copyIn(srcName: string, destPath: string): Promise<void> {
    Paths.ensureDir(destPath.substring(0, destPath.lastIndexOf('/')));
    await fs.copyFile(DeployImport.tmpPath(srcName), destPath);
  }

  /**
   * Imports a runtime pack zip named like `jre21-ohos-x86_64.zip` (the
   * name encodes the Java major version and the ABI). Modern packs root at
   * `lib/server/`; JDK8 packs root at `jre/lib/<arch>/server/`. Extracts to
   * jvm/<base>/ and writes the runtime.json marker with the normalized JRE
   * root.
   */
  public static async importRuntimePack(zipName: string): Promise<string> {
    if (!zipName.endsWith('.zip')) {
      return 'Runtime pack must be a .zip, e.g. jre21-ohos-x86_64.zip';
    }
    const base: string = zipName.substring(0, zipName.length - 4);
    const majorMatch: RegExpExecArray | null = /(?:jre|jdk)(\d+)/.exec(base);
    const abiMatch: RegExpExecArray | null = /ohos-(\S+)$/.exec(base);
    if (majorMatch === null) {
      return 'Zip name must encode the Java version, e.g. jre21-ohos-x86_64.zip';
    }
    try {
      const destZip: string = `${Paths.jvmDir()}/${zipName}`;
      Paths.ensureDir(Paths.jvmDir());
      await DeployImport.copyIn(zipName, destZip);
      const destDir: string = Paths.jvmRuntimeDir(base);
      Paths.ensureDir(destDir);
      await zlib.decompressFile(destZip, destDir);
      const homePath: string = JavaRuntimeManager.findJvmHome(destDir);
      if (homePath.length === 0) {
        fs.unlinkSync(destZip);
        return `Runtime pack ${base} contains no discoverable libjvm.so`;
      }
      const abi: string = abiMatch !== null ? abiMatch[1] : Paths.deviceAbi();
      const descriptor: RuntimeDescriptor = {
        name: base,
        javaMajor: Number(majorMatch[1]),
        abi: abi,
        homePath: homePath
      };
      Paths.writeTextFileSync(`${destDir}/runtime.json`, JSON.stringify(descriptor));
      fs.unlinkSync(destZip);
      return `Runtime pack imported: ${base} (Java ${majorMatch[1]}, ${abi})`;
    } catch (err) {
      const e = err as Error;
      return `Runtime pack import failed: ${e.message}`;
    }
  }

  private static stageBundledJar(resourceName: string, version: string): boolean {
    const bridgeDir: string = `${Paths.base()}/bridge`;
    const dest: string = `${bridgeDir}/${resourceName}`;
    const marker: string = `${dest}.version`;
    try {
      if (fs.accessSync(dest) && fs.accessSync(marker) &&
        fs.readTextSync(marker) === version) {
        return true;
      }
      const data: Uint8Array = getContext().resourceManager
        .getRawFileContentSync(`bridge/${resourceName}`);
      Paths.ensureDir(bridgeDir);
      const part: string = `${dest}.part`;
      const out = fs.openSync(part,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        const bytes: ArrayBuffer =
          data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
        fs.writeSync(out.fd, bytes);
      } finally {
        fs.closeSync(out);
      }
      if (fs.accessSync(dest)) {
        fs.unlinkSync(dest);
      }
      fs.renameSync(part, dest);
      Paths.writeTextFileSync(marker, version);
      return true;
    } catch (err) {
      return false;
    }
  }

  public static ensureBundledBridge(): boolean {
    return DeployImport.stageBundledJar('mc4hos-bridge.jar', '1.0.0');
  }

  public static ensureBundledLwjgl(): boolean {
    return DeployImport.stageBundledJar(LWJGL_JAR_NAME, LWJGL_GENERATION);
  }
}
