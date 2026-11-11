/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import fs from '@ohos.file.fs';
import zlib from '@ohos.zlib';
import { downloadToFile } from '../common/Http';
import { JsonObj, parseJson, getStr, getNum } from '../common/JsonReader';
import { Logger } from '../common/Logger';
import { Paths } from '../common/Paths';

/**
 * Embedded Java runtime manager.
 *
 * MC4HOS does not bundle a JVM in the repository. Instead, OpenHarmony
 * OpenJDK builds are packaged as **runtime packs** — standard zip archives
 * containing a JRE image rooted at the archive root (`bin/`, `lib/`,
 * `release`, plus `libjvm.so` under `lib/server/`) and a `runtime.json`
 * descriptor. Packs are downloaded from the URL configured per runtime and
 * extracted under `<filesDir>/mc4hos/jvm/<name>/`. See docs/NATIVES.md for
 * how to produce a pack from OpenJDK sources.
 */

const TAG: string = 'JavaRuntime';

export interface RuntimeDescriptor {
  name: string;
  javaMajor: number;
  homePath: string;
}

export interface RuntimePackSource {
  name: string;
  javaMajor: number;
  /** ABI the pack was built for: "arm64-v8a" or "x86_64". */
  abi: string;
  packUrl: string;
  sha1: string;
}

/**
 * Runtime pack catalog. Distributors point these entries at their own
 * build pipeline output; the URLs below are placeholders. MC4HOS ships no
 * runtime binaries. Both OHOS NDK 64-bit ABIs are covered — arm64-v8a for
 * phones/tablets, x86_64 for Intel 2-in-1s and the emulator (there is no
 * 32-bit x86 ABI in the OHOS NDK).
 */
const RUNTIME_CATALOG: Array<RuntimePackSource> = [
  { name: 'jre8-ohos-aarch64', javaMajor: 8, abi: 'arm64-v8a', packUrl: '', sha1: '' },
  { name: 'jre8-ohos-x86_64', javaMajor: 8, abi: 'x86_64', packUrl: '', sha1: '' },
  { name: 'jre17-ohos-aarch64', javaMajor: 17, abi: 'arm64-v8a', packUrl: '', sha1: '' },
  { name: 'jre17-ohos-x86_64', javaMajor: 17, abi: 'x86_64', packUrl: '', sha1: '' },
  { name: 'jre21-ohos-aarch64', javaMajor: 21, abi: 'arm64-v8a', packUrl: '', sha1: '' },
  { name: 'jre21-ohos-x86_64', javaMajor: 21, abi: 'x86_64', packUrl: '', sha1: '' }
];

export class JavaRuntimeManager {
  /** Lists installed runtimes by scanning for `runtime.json` markers. */
  public static listInstalled(): Array<RuntimeDescriptor> {
    const out: Array<RuntimeDescriptor> = [];
    try {
      if (!fs.accessSync(Paths.jvmDir())) {
        return out;
      }
      const names: Array<string> = fs.listFileSync(Paths.jvmDir());
      for (const name of names) {
        const marker: string = `${Paths.jvmRuntimeDir(name)}/runtime.json`;
        if (!fs.accessSync(marker)) {
          continue;
        }
        const root: JsonObj | null = parseJson(fs.readTextSync(marker));
        if (root === null) {
          continue;
        }
        out.push({
          name: getStr(root, 'name', name),
          javaMajor: getNum(root, 'javaMajor', 8),
          homePath: getStr(root, 'homePath', Paths.jvmRuntimeDir(name))
        });
      }
    } catch (err) {
      const e = err as Error;
      Logger.warn(TAG, `listInstalled failed: ${e.message}`);
    }
    return out;
  }

  /** Picks the runtime whose major version satisfies the game requirement. */
  public static selectFor(javaMajorRequired: number): RuntimeDescriptor | null {
    const installed: Array<RuntimeDescriptor> = JavaRuntimeManager.listInstalled();
    // exact match first, then nearest newer, then any
    let best: RuntimeDescriptor | null = null;
    for (const r of installed) {
      if (r.javaMajor === javaMajorRequired) {
        return r;
      }
      if (r.javaMajor > javaMajorRequired && (best === null || r.javaMajor < best.javaMajor)) {
        best = r;
      }
    }
    if (best !== null) {
      return best;
    }
    return installed.length > 0 ? installed[0] : null;
  }

  /** Catalog entry matching a required major version AND the device ABI. */
  public static catalogFor(javaMajorRequired: number): RuntimePackSource | null {
    const abi: string = Paths.deviceAbi();
    let sameMajorAnyAbi: RuntimePackSource | null = null;
    for (const pack of RUNTIME_CATALOG) {
      if (pack.javaMajor === javaMajorRequired) {
        if (pack.abi === abi) {
          return pack;
        }
        if (sameMajorAnyAbi === null) {
          sameMajorAnyAbi = pack;
        }
      }
    }
    return sameMajorAnyAbi;
  }

  /**
   * Downloads and installs a runtime pack. The zip is extracted to
   * `jvm/<name>/` and a `runtime.json` marker is written on success.
   */
  public static async install(pack: RuntimePackSource,
    onProgress?: (received: number, total: number) => void): Promise<boolean> {
    if (pack.packUrl.length === 0) {
      Logger.error(TAG,
        `runtime pack ${pack.name} (${pack.abi}) has no URL configured — see docs/NATIVES.md`);
      return false;
    }
    const deviceAbi: string = Paths.deviceAbi();
    if (pack.abi !== deviceAbi) {
      Logger.warn(TAG, `pack ${pack.name} is ${pack.abi} but device is ${deviceAbi}; ` +
        'the JVM will fail to load — build a matching pack');
    }
    const destDir: string = Paths.jvmRuntimeDir(pack.name);
    const zipPath: string = `${Paths.jvmDir()}/${pack.name}.zip`;
    const marker: string = `${destDir}/runtime.json`;
    if (fs.accessSync(marker)) {
      Logger.info(TAG, `runtime ${pack.name} already installed`);
      return true;
    }
    Paths.ensureDir(Paths.jvmDir());
    const code: number = await downloadToFile(pack.packUrl, {
      destPath: zipPath,
      onProgress: onProgress
    });
    if (!(code >= 200 && code < 300)) {
      Logger.error(TAG, `runtime pack download failed: HTTP ${code}`);
      return false;
    }
    try {
      await zlib.decompressFile(zipPath, destDir);
      Logger.info(TAG, `runtime ${pack.name} extracted to ${destDir}`);
    } catch (err) {
      const e = err as Error;
      Logger.error(TAG, `runtime extraction failed: ${e.message}`);
      return false;
    } finally {
      try {
        if (fs.accessSync(zipPath)) {
          fs.unlinkSync(zipPath);
        }
      } catch (cleanupErr) {
        // best effort
      }
    }
    const descriptor: JsonObj = {
      name: pack.name,
      javaMajor: pack.javaMajor,
      abi: pack.abi,
      homePath: destDir
    };
    fs.writeTextSync(marker, JSON.stringify(descriptor));
    return true;
  }

  /**
   * Ensures a suitable runtime exists for the required major version,
   * downloading one from the catalog when necessary.
   */
  public static async ensureRuntime(javaMajorRequired: number): Promise<RuntimeDescriptor | null> {
    const existing: RuntimeDescriptor | null = JavaRuntimeManager.selectFor(javaMajorRequired);
    if (existing !== null) {
      return existing;
    }
    const pack: RuntimePackSource | null = JavaRuntimeManager.catalogFor(javaMajorRequired);
    if (pack === null) {
      return null;
    }
    const ok: boolean = await JavaRuntimeManager.install(pack);
    return ok ? JavaRuntimeManager.selectFor(javaMajorRequired) : null;
  }
}
