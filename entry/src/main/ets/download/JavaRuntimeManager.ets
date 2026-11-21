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
import { downloadToFile, getJson } from '../common/Http';
import { sha256HexOf } from './DownloadShared';
import {
  JsonObj, parseJson, getStr, getNum, asArray, asObj
} from '../common/JsonReader';
import { Logger } from '../common/Logger';
import { Paths } from '../common/Paths';

/**
 * Embedded Java runtime manager.
 *
 * MC4HOS does not bundle a JVM. OpenHarmony OpenJDK builds are packaged as
 * **runtime packs**: zip archives containing a complete JRE/JDK image and a
 * `runtime.json` descriptor written at install time. Modern packs root at
 * `bin/`, `lib/`, `release`; JDK8 packs root at `jre/` with the VM under
 * `lib/<arch>/server/`. Both layouts are normalized to the JRE root here.
 *
 * aarch64 packs come from the public OHOS OpenJDK builds. x86_64 packs are
 * produced by the separate `openharmony-jdk/` tree and its GitHub Actions
 * workflow; see docs/NATIVES.md.
 */

const TAG: string = 'JavaRuntime';

const COMMUNITY_RELEASE_BASE: string =
  'https://github.com/LZZLHY/mc-ohos-resources/releases/download';
const X86_RELEASE_BASE: string =
  'https://github.com/BytinIsDead/MC4HOS/releases/download/jdk-x86_64-v1';

export interface RuntimeDescriptor {
  name: string;
  javaMajor: number;
  /** ABI the runtime was built for ("arm64-v8a" / "x86_64"). */
  abi?: string;
  homePath: string;
}

export interface RuntimePackSource {
  name: string;
  javaMajor: number;
  /** ABI the pack was built for: "arm64-v8a" or "x86_64". */
  abi: string;
  packUrl: string;
  sha256: string;
  sizeBytes: number;
}

/**
 * Built-in runtime catalog. The aarch64 entries are pinned to verified
 * community releases. The x86_64 21/25 entries point at the release produced
 * by `.github/workflows/jdk-x86_64.yml`; their checksums are refreshed at
 * install time from that release's `runtime-catalog.json`. Java 8/17 are not
 * part of the x86_64 build matrix — install a newer runtime for those games
 * or import a pack manually.
 */
const RUNTIME_CATALOG: Array<RuntimePackSource> = [
  {
    name: 'jre8-ohos-aarch64', javaMajor: 8, abi: 'arm64-v8a',
    packUrl: `${COMMUNITY_RELEASE_BASE}/v8u452-ohos-4/jdk8-ohos-full-v4.zip`,
    sha256: '02c2cedb3539682de3df3d7870b855bfefaac1f4cfe53951cfe90b0dea3d3a63',
    sizeBytes: 39555296
  },
  {
    name: 'jre17-ohos-aarch64', javaMajor: 17, abi: 'arm64-v8a',
    packUrl: `${COMMUNITY_RELEASE_BASE}/v17.0.13-ohos-5/jdk17-ohos-full-v5.zip`,
    sha256: '0e26b0dece38156838456cfb12058d863aa9856cdd8fd648f06f9bc5e91f8ecd',
    sizeBytes: 113762513
  },
  {
    name: 'jre21-ohos-aarch64', javaMajor: 21, abi: 'arm64-v8a',
    packUrl: `${COMMUNITY_RELEASE_BASE}/v21.0.5-ohos-7/jdk21-ohos-full-v7.zip`,
    sha256: '21556d0d4fc5eea09ba27068cf8a96803bb1667b35adbc8495fdc5f831316275',
    sizeBytes: 114267146
  },
  {
    name: 'jre25-ohos-aarch64', javaMajor: 25, abi: 'arm64-v8a',
    packUrl: `${COMMUNITY_RELEASE_BASE}/v25.0.4-ohos-2/jdk25-ohos-full-v2.zip`,
    sha256: 'd8e31df5d199a9b34d6d13c188b71af19c2fb1738da7bf3c6eeaed89a0a37538',
    sizeBytes: 118872200
  },
  { name: 'jre8-ohos-x86_64', javaMajor: 8, abi: 'x86_64', packUrl: '', sha256: '', sizeBytes: 0 },
  { name: 'jre17-ohos-x86_64', javaMajor: 17, abi: 'x86_64', packUrl: '', sha256: '', sizeBytes: 0 },
  {
    name: 'jre21-ohos-x86_64', javaMajor: 21, abi: 'x86_64',
    packUrl: `${X86_RELEASE_BASE}/jre21-ohos-x86_64.zip`, sha256: '', sizeBytes: 0
  },
  {
    name: 'jre25-ohos-x86_64', javaMajor: 25, abi: 'x86_64',
    packUrl: `${X86_RELEASE_BASE}/jre25-ohos-x86_64.zip`, sha256: '', sizeBytes: 0
  }
];

const runtimeCatalog: Array<RuntimePackSource> = RUNTIME_CATALOG;

export class JavaRuntimeManager {
  private static remoteCatalogLoaded: boolean = false;

  /**
   * Fetches the x86_64 release catalog once per process and applies its
   * pinned checksums to matching built-in entries. Failure is non-fatal: the
   * built-in URLs still work, but downloads then lack a pinned digest.
   */
  public static async refreshCatalog(): Promise<void> {
    if (JavaRuntimeManager.remoteCatalogLoaded) {
      return;
    }
    JavaRuntimeManager.remoteCatalogLoaded = true;
    const response = await getJson(`${X86_RELEASE_BASE}/runtime-catalog.json`,
      { 'Accept': 'application/json' });
    if (!response.ok || response.body.length === 0) {
      Logger.warn(TAG, `x86_64 runtime catalog unavailable (HTTP ${response.code})`);
      return;
    }
    let root: Object | null = null;
    try {
      root = JSON.parse(response.body) as Object;
    } catch (err) {
      Logger.warn(TAG, 'x86_64 runtime catalog is not valid JSON');
      return;
    }
    if (root === null) {
      return;
    }
    const entries = asArray(root);
    if (entries === null) {
      return;
    }
    for (const raw of entries) {
      const obj = asObj(raw);
      if (obj === null) {
        continue;
      }
      const name: string = getStr(obj, 'name');
      const url: string = getStr(obj, 'packUrl');
      const sha256: string = getStr(obj, 'sha256').toLowerCase();
      const major: number = getNum(obj, 'javaMajor');
      const size: number = getNum(obj, 'sizeBytes');
      if (name.length === 0 || major === 0 || sha256.length !== 64 || size <= 0) {
        continue;
      }
      // Only accept packs hosted by this repository's release; a remote
      // catalog must not be able to redirect runtime downloads elsewhere.
      if (!url.startsWith(`${X86_RELEASE_BASE}/`)) {
        continue;
      }
      for (let i = 0; i < runtimeCatalog.length; i++) {
        if (runtimeCatalog[i].name === name) {
          runtimeCatalog[i] = {
            name: name,
            javaMajor: major,
            abi: getStr(obj, 'abi', 'x86_64'),
            packUrl: url,
            sha256: sha256,
            sizeBytes: size
          };
        }
      }
    }
  }

  /** Finds the JRE/JDK root containing a usable libjvm.so, or ''. */
  public static findJvmHome(root: string): string {
    if (root.length === 0) {
      return '';
    }
    if (JavaRuntimeManager.hasJvm(root)) {
      return root;
    }
    const level1: Array<string> = [`${root}/jre`];
    for (const dir of JavaRuntimeManager.subdirs(root)) {
      if (dir !== `${root}/jre`) {
        level1.push(dir);
      }
    }
    for (const dir of level1) {
      if (JavaRuntimeManager.hasJvm(dir)) {
        return dir;
      }
    }
    for (const dir of level1) {
      const nested: Array<string> = [`${dir}/jre`];
      for (const child of JavaRuntimeManager.subdirs(dir)) {
        nested.push(child);
      }
      for (const candidate of nested) {
        if (JavaRuntimeManager.hasJvm(candidate)) {
          return candidate;
        }
      }
    }
    return '';
  }

  /** Directories to put on the JVM library path for an installed runtime. */
  public static nativeLibraryDirs(javaHome: string): Array<string> {
    const arch: string = Paths.deviceAbi() === 'arm64-v8a' ? 'aarch64' : 'x86_64';
    const rels: Array<string> = ['lib/server', 'lib', `lib/${arch}/server`, `lib/${arch}`];
    const dirs: Array<string> = [];
    for (const rel of rels) {
      const dir: string = `${javaHome}/${rel}`;
      if (fs.accessSync(dir) && dirs.indexOf(dir) < 0) {
        dirs.push(dir);
      }
    }
    return dirs;
  }

  private static hasJvm(dir: string): boolean {
    const arch: string = Paths.deviceAbi() === 'arm64-v8a' ? 'aarch64' : 'x86_64';
    const rels: Array<string> = [
      'lib/server/libjvm.so',
      `lib/${arch}/server/libjvm.so`,
      'lib/arm64/server/libjvm.so'
    ];
    for (const rel of rels) {
      if (fs.accessSync(`${dir}/${rel}`)) {
        return true;
      }
    }
    return false;
  }

  private static subdirs(dir: string): Array<string> {
    const out: Array<string> = [];
    try {
      for (const name of fs.listFileSync(dir)) {
        const path: string = `${dir}/${name}`;
        try {
          if (fs.statSync(path).isDirectory()) {
            out.push(path);
          }
        } catch (err) {
          // vanished or unreadable entry; skip
        }
      }
    } catch (err) {
      // not a directory
    }
    return out;
  }

  /** Lists installed runtimes by scanning for `runtime.json` markers. */
  public static listInstalled(): Array<RuntimeDescriptor> {
    const out: Array<RuntimeDescriptor> = [];
    try {
      if (!fs.accessSync(Paths.jvmDir())) {
        return out;
      }
      const names: Array<string> = fs.listFileSync(Paths.jvmDir());
      for (const name of names) {
        const destDir: string = Paths.jvmRuntimeDir(name);
        const marker: string = `${destDir}/runtime.json`;
        if (!fs.accessSync(marker)) {
          continue;
        }
        const root: JsonObj | null = parseJson(fs.readTextSync(marker));
        if (root === null) {
          continue;
        }
        const storedHome: string = getStr(root, 'homePath', destDir);
        const homePath: string = JavaRuntimeManager.findJvmHome(storedHome);
        if (homePath.length === 0) {
          Logger.warn(TAG, `runtime ${name} has no discoverable libjvm.so; ignoring`);
          continue;
        }
        const descriptor: RuntimeDescriptor = {
          name: getStr(root, 'name', name),
          javaMajor: getNum(root, 'javaMajor', 8),
          homePath: homePath
        };
        const abi: string = getStr(root, 'abi');
        if (abi.length > 0) {
          descriptor.abi = abi;
        }
        out.push(descriptor);
      }
    } catch (err) {
      const e = err as Error;
      Logger.warn(TAG, `listInstalled failed: ${e.message}`);
    }
    return out;
  }

  /** Any installed runtime for this device — used by the JVM self-test. */
  public static firstInstalled(): RuntimeDescriptor | null {
    const installed: Array<RuntimeDescriptor> = JavaRuntimeManager.listInstalled();
    const abi: string = Paths.deviceAbi();
    for (const r of installed) {
      if (r.abi === undefined || r.abi === abi) {
        return r;
      }
    }
    return null;
  }

  /** Picks the runtime whose major version satisfies the game requirement. */
  public static selectFor(javaMajorRequired: number): RuntimeDescriptor | null {
    const installed: Array<RuntimeDescriptor> = JavaRuntimeManager.listInstalled();
    const abi: string = Paths.deviceAbi();
    // Exact match first, otherwise the nearest newer major. Never run a
    // major older than the game requires — class file versions would fail.
    let best: RuntimeDescriptor | null = null;
    for (const r of installed) {
      if (r.abi !== undefined && r.abi !== abi) {
        continue;
      }
      if (r.javaMajor === javaMajorRequired) {
        return r;
      }
      if (r.javaMajor > javaMajorRequired && (best === null || r.javaMajor < best.javaMajor)) {
        best = r;
      }
    }
    return best;
  }

  /** Catalog entry matching a required major version AND the device ABI. */
  public static catalogFor(javaMajorRequired: number): RuntimePackSource | null {
    const abi: string = Paths.deviceAbi();
    for (const pack of runtimeCatalog) {
      if (pack.javaMajor === javaMajorRequired && pack.abi === abi) {
        return pack;
      }
    }
    for (const pack of runtimeCatalog) {
      if (pack.javaMajor === javaMajorRequired) {
        Logger.warn(TAG,
          `no Java ${javaMajorRequired} pack for ${abi}; catalog only has ${pack.abi}`);
        break;
      }
    }
    return null;
  }

  /**
   * Downloads and installs a runtime pack. The zip is extracted to
   * `jvm/<name>/`, the JRE root is normalized, and a `runtime.json` marker is
   * written on success.
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
      Logger.error(TAG, `pack ${pack.name} is ${pack.abi} but device is ${deviceAbi}`);
      return false;
    }
    const destDir: string = Paths.jvmRuntimeDir(pack.name);
    const zipPath: string = `${Paths.jvmDir()}/${pack.name}.zip`;
    const marker: string = `${destDir}/runtime.json`;
    if (fs.accessSync(marker) && JavaRuntimeManager.findJvmHome(destDir).length > 0) {
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
    if (pack.sizeBytes > 0) {
      const actualSize: number = fs.statSync(zipPath).size;
      if (actualSize !== pack.sizeBytes) {
        Logger.error(TAG,
          `runtime pack size mismatch: expected ${pack.sizeBytes}, got ${actualSize}`);
        fs.unlinkSync(zipPath);
        return false;
      }
    }
    if (pack.sha256.length > 0) {
      const actual: string = await sha256HexOf(zipPath);
      if (actual !== pack.sha256.toLowerCase()) {
        Logger.error(TAG, `runtime pack sha256 mismatch: expected ${pack.sha256}, got ${actual}`);
        fs.unlinkSync(zipPath);
        return false;
      }
    } else {
      Logger.warn(TAG, `runtime pack ${pack.name} has no pinned sha256`);
    }
    Paths.ensureDir(destDir);
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
    const homePath: string = JavaRuntimeManager.findJvmHome(destDir);
    if (homePath.length === 0) {
      Logger.error(TAG, `runtime ${pack.name} extracted without a discoverable libjvm.so`);
      return false;
    }
    const descriptor: RuntimeDescriptor = {
      name: pack.name,
      javaMajor: pack.javaMajor,
      abi: pack.abi,
      homePath: homePath
    };
    Paths.writeTextFileSync(marker, JSON.stringify(descriptor));
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
    await JavaRuntimeManager.refreshCatalog();
    const pack: RuntimePackSource | null = JavaRuntimeManager.catalogFor(javaMajorRequired);
    if (pack === null) {
      return null;
    }
    const ok: boolean = await JavaRuntimeManager.install(pack);
    return ok ? JavaRuntimeManager.selectFor(javaMajorRequired) : null;
  }
}
