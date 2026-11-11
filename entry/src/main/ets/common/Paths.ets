/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import fs from '@ohos.file.fs';
import common from '@ohos.app.ability.common';
import bundleManager from '@ohos.bundle.bundleManager';
import deviceInfo from '@ohos.deviceInfo';
import { Logger } from './Logger';

/**
 * Centralized filesystem layout. Everything lives inside the application
 * sandbox under `<filesDir>/mc4hos`:
 *
 *   versions/    per-version JSON + client jars
 *   libraries/   maven-layout dependency jars
 *   assets/      asset index JSONs + hashed object pool
 *   jvm/         embedded Java runtimes (one sub-directory per runtime,
 *                runtime names carry their ABI: jre17-ohos-x86_64 …)
 *   natives/     platform native libraries per game version AND ABI
 *                (liblwjgl.so, libopenal.so, …)
 *   logs/        captured JVM output
 *   saves/       game_directory (worlds, options.txt, screenshots)
 */
export class Paths {
  private static baseDir: string = '';

  /** Must be called once from EntryAbility.onCreate with the ability context. */
  public static init(context: common.UIAbilityContext): void {
    Paths.baseDir = `${context.filesDir}/mc4hos`;
    Paths.ensureDir(Paths.baseDir);
    Paths.ensureDir(Paths.versionsDir());
    Paths.ensureDir(Paths.librariesDir());
    Paths.ensureDir(Paths.assetsDir());
    Paths.ensureDir(Paths.indexesDir());
    Paths.ensureDir(Paths.objectsDir());
    Paths.ensureDir(Paths.jvmDir());
    Paths.ensureDir(Paths.nativesDir());
    Paths.ensureDir(Paths.logsDir());
    Paths.ensureDir(Paths.gameDir());
  }

  public static base(): string {
    return Paths.baseDir;
  }

  public static versionsDir(): string {
    return `${Paths.baseDir}/versions`;
  }

  public static versionDir(versionId: string): string {
    return `${Paths.versionsDir()}/${versionId}`;
  }

  public static clientJarPath(versionId: string): string {
    return `${Paths.versionDir(versionId)}/${versionId}.jar`;
  }

  public static versionJsonPath(versionId: string): string {
    return `${Paths.versionDir(versionId)}/${versionId}.json`;
  }

  public static manifestCachePath(): string {
    return `${Paths.versionsDir()}/version_manifest_v2.json`;
  }

  public static librariesDir(): string {
    return `${Paths.baseDir}/libraries`;
  }

  /** Converts a maven coordinate (group:artifact:version) to its on-disk path. */
  public static libraryPath(group: string, artifact: string, version: string): string {
    return `${Paths.librariesDir()}/${group.replace(/\./g, '/')}/${artifact}/${version}/${artifact}-${version}.jar`;
  }

  public static assetsDir(): string {
    return `${Paths.baseDir}/assets`;
  }

  public static indexesDir(): string {
    return `${Paths.assetsDir()}/indexes`;
  }

  public static objectsDir(): string {
    return `${Paths.assetsDir()}/objects`;
  }

  public static assetIndexPath(indexId: string): string {
    return `${Paths.indexesDir()}/${indexId}.json`;
  }

  public static assetObjectPath(hash: string): string {
    return `${Paths.objectsDir()}/${hash.substring(0, 2)}/${hash}`;
  }

  public static jvmDir(): string {
    return `${Paths.baseDir}/jvm`;
  }

  public static jvmRuntimeDir(runtimeName: string): string {
    return `${Paths.jvmDir()}/${runtimeName}`;
  }

  public static nativesDir(): string {
    return `${Paths.baseDir}/natives`;
  }

  /**
   * Natives live per game version AND per ABI, e.g.
   * `natives/1.20.4/x86_64/liblwjgl.so` — a device only ever loads its own
   * architecture, and the same sandbox can hold both.
   */
  public static nativesVersionDir(versionId: string): string {
    return `${Paths.nativesDir()}/${versionId}/${Paths.deviceAbi()}`;
  }

  public static logsDir(): string {
    return `${Paths.baseDir}/logs`;
  }

  public static gameDir(): string {
    return `${Paths.baseDir}/game`;
  }

  /**
   * Directory of the application's packaged native libraries (.so files
   * shipped inside the HAP), retrieved through BundleManager.
   */
  public static hapNativeLibraryDir(): string {
    return Paths.hapNativeLibDir;
  }

  private static hapNativeLibDir: string = '';

  /** Resolves applicationInfo.nativeLibraryPath (async because BundleManager is). */
  public static async initHapNativeLibraryDir(): Promise<void> {
    try {
      const info = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      Paths.hapNativeLibDir = info.appInfo.nativeLibraryPath;
      Logger.info('Paths', `HAP native library dir: ${Paths.hapNativeLibDir}`);
    } catch (err) {
      const e = err as Error;
      Logger.warn('Paths', `nativeLibraryPath unavailable: ${e.message}`);
    }
  }

  public static ensureDir(path: string): void {
    try {
      if (!fs.accessSync(path)) {
        fs.mkdirSync(path, true);
      }
    } catch (err) {
      const e = err as Error;
      Logger.warn('Paths', `ensureDir ${path} failed: ${e.message}`);
    }
  }

  /**
   * This SDK's fs API has no writeTextSync; text writes go through an fd.
   * Creates/truncates the target file, then writes the whole string.
   */
  public static writeTextFileSync(path: string, text: string): void {
    const file: fs.File =
      fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, text);
    } finally {
      fs.closeSync(file.fd);
    }
  }

  private static cachedAbi: string = '';

  /**
   * The device's primary 64-bit ABI, parsed from `deviceInfo.abiList`
   * (e.g. "arm64-v8a" on phones/tablets, "x86_64" on Intel 2-in-1s and the
   * emulator). Used to pick matching runtime packs and natives. The OHOS
   * NDK exposes no 32-bit x86 ABI, so the only x86 target is x86_64.
   */
  public static deviceAbi(): string {
    if (Paths.cachedAbi.length > 0) {
      return Paths.cachedAbi;
    }
    let abi: string = 'arm64-v8a';
    try {
      const list: string = deviceInfo.abiList;
      const parts: Array<string> = list.split(',').map((s: string) => s.trim());
      if (parts.indexOf('arm64-v8a') >= 0) {
        abi = 'arm64-v8a';
      } else if (parts.indexOf('x86_64') >= 0) {
        abi = 'x86_64';
      } else if (parts.length > 0 && parts[0].length > 0) {
        abi = parts[0];
      }
    } catch (err) {
      const e = err as Error;
      Logger.warn('Paths', `abiList unavailable, defaulting to arm64-v8a: ${e.message}`);
    }
    Paths.cachedAbi = abi;
    Logger.info('Paths', `device ABI: ${abi}`);
    return abi;
  }
}
