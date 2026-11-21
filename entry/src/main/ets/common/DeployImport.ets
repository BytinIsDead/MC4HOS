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

/**
 * In-app deployment importer.
 *
 * `hdc file send` into an app sandbox often fails with "No such file or
 * directory" / permission errors — but /data/local/tmp is world-writable,
 * so the reliable flow is:
 *
 *   hdc file send jre17-ohos-x86_64.zip /data/local/tmp/
 *   hdc file send mc4hos-bridge.jar    /data/local/tmp/
 *   hdc file send natives-1.21.4.zip   /data/local/tmp/
 *
 * …then import from the Settings page. The app copies the files into its
 * own sandbox and extracts them.
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

  /** Imports mc4hos-bridge.jar from /data/local/tmp into bridge/. */
  public static async importBridgeJar(): Promise<string> {
    try {
      const bridgeDir: string = `${Paths.base()}/bridge`;
      Paths.ensureDir(bridgeDir);
      await DeployImport.copyIn('mc4hos-bridge.jar', `${bridgeDir}/mc4hos-bridge.jar`);
      return 'Bridge jar imported (classpath-ready)';
    } catch (err) {
      const e = err as Error;
      return `Bridge import failed: ${e.message} — send mc4hos-bridge.jar to ${TMP_DIR} first`;
    }
  }

  /**
   * Imports a natives zip named `natives-<mcVersion>.zip` whose root
   * contains the lib*.so files for the device ABI. Extracts to
   * natives/<mcVersion>/<abi>/.
   */
  public static async importNativesZip(mcVersion: string): Promise<string> {
    if (mcVersion.length === 0) {
      return 'Enter the Minecraft version the natives were built for';
    }
    try {
      const destDir: string = Paths.nativesVersionDir(mcVersion);
      Paths.ensureDir(destDir);
      await DeployImport.copyIn(`natives-${mcVersion}.zip`, `${Paths.nativesDir()}/natives-${mcVersion}.zip`);
      await zlib.decompressFile(`${Paths.nativesDir()}/natives-${mcVersion}.zip`, destDir);
      fs.unlinkSync(`${Paths.nativesDir()}/natives-${mcVersion}.zip`);
      return `Natives imported for ${mcVersion} (${Paths.deviceAbi()})`;
    } catch (err) {
      const e = err as Error;
      return `Natives import failed: ${e.message}`;
    }
  }
}
