/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import fs from '@ohos.file.fs';
import { getJson } from '../common/Http';
import { JsonObj, parseJson, getStr, getNum, getArr, getObj } from '../common/JsonReader';
import { Logger } from '../common/Logger';
import { Paths } from '../common/Paths';

/**
 * Official version metadata access.
 *
 * Fetches and caches `version_manifest_v2.json` (list of all released
 * versions) and the per-version descriptor JSON that drives the installer and
 * the JVM argument builder. The JSON schema is the vanilla launcher protocol;
 * parsing is done clean-room via typed readers.
 */

const TAG: string = 'VersionManifest';

const MANIFEST_URL: string =
  'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json';
export const DEFAULT_LIBRARIES_REPO: string = 'https://libraries.minecraft.net/';
export const DEFAULT_ASSETS_BASE: string = 'https://resources.download.minecraft.net';
export const DEFAULT_META_BASE: string = 'https://piston-meta.mojang.com';

export interface VersionEntry {
  id: string;
  type: string; // release | snapshot | old_beta | old_alpha
  url: string;
  releaseTime: string;
}

export interface RuleSet {
  action: string;
  osName?: string;
  osArch?: string;
  features?: JsonObj;
}

/** A rule-gated argument (modern `arguments.jvm`/`arguments.game` entries). */
export interface ArgEntry {
  raw?: string;
  values?: Array<string>;
  rules?: Array<RuleSet>;
}

export interface LibDownload {
  coord: string;       // group:artifact:version
  url: string;
  destPath: string;
  sha1: string;
  sizeBytes: number;
}

export interface LibNatives {
  coord: string;
  /** e.g. "natives-linux" — MC4HOS ignores these classifiers and instead
   *  loads OpenHarmony-built natives from Paths.nativesDir(). */
  classifier: string;
}

export interface LibraryEntry {
  name: string;
  download: LibDownload | null;
  natives: LibNatives | null;
  rules: Array<RuleSet>;
}

export interface ClientDownload {
  url: string;
  sha1: string;
  sizeBytes: number;
}

export interface VersionJson {
  id: string;
  type: string;
  mainClass: string;
  client: ClientDownload | null;
  libraries: Array<LibraryEntry>;
  jvmArgs: Array<ArgEntry>;
  gameArgs: Array<ArgEntry>;
  legacyMinecraftArguments: string;
  assetIndexId: string;
  assetIndexUrl: string;
  javaMajorVersion: number;
}

export class VersionManifest {
  private entries: Array<VersionEntry> = [];
  private cache: Map<string, VersionJson> = new Map();

  public list(): Array<VersionEntry> {
    return this.entries;
  }

  public cachedVersion(versionId: string): VersionJson | null {
    return this.cache.get(versionId) ?? null;
  }

  /**
   * Load the manifest, preferring the on-disk cache for instant startup and
   * refreshing from the network in the background.
   */
  public async load(refreshNetwork: boolean = true): Promise<Array<VersionEntry>> {
    if (fs.accessSync(Paths.manifestCachePath())) {
      const cached: string = fs.readTextSync(Paths.manifestCachePath());
      this.parseManifest(cached);
      Logger.info(TAG, `manifest cache: ${this.entries.length} versions`);
    }
    if (refreshNetwork || this.entries.length === 0) {
      const resp = await getJson(MANIFEST_URL);
      if (resp.ok) {
        fs.writeTextSync(Paths.manifestCachePath(), resp.body);
        this.parseManifest(resp.body);
        Logger.info(TAG, `manifest fetched: ${this.entries.length} versions`);
      } else if (this.entries.length === 0) {
        Logger.error(TAG, 'manifest unavailable offline');
      }
    }
    return this.entries;
  }

  private parseManifest(body: string): void {
    const root: JsonObj | null = parseJson(body);
    if (root === null) {
      return;
    }
    const versions: Array<Object> | null = getArr(root, 'versions');
    if (versions === null) {
      return;
    }
    const parsed: Array<VersionEntry> = [];
    for (const item of versions) {
      const v: JsonObj | null = item as JsonObj;
      if (v === null) {
        continue;
      }
      parsed.push({
        id: getStr(v, 'id'),
        type: getStr(v, 'type'),
        url: getStr(v, 'url'),
        releaseTime: getStr(v, 'releaseTime')
      });
    }
    this.entries = parsed;
  }

  /** Fetch (and cache) the per-version JSON descriptor. */
  public async fetchVersion(versionId: string): Promise<VersionJson | null> {
    const cached: VersionJson | null = this.cache.get(versionId) ?? null;
    if (cached !== null) {
      return cached;
    }
    const entry: VersionEntry | undefined =
      this.entries.find((e: VersionEntry) => e.id === versionId);
    const jsonPath: string = Paths.versionJsonPath(versionId);
    let body: string = '';
    if (fs.accessSync(jsonPath)) {
      body = fs.readTextSync(jsonPath);
    } else if (entry !== undefined && entry.url.length > 0) {
      const resp = await getJson(entry.url);
      if (!resp.ok) {
        Logger.error(TAG, `version json fetch failed for ${versionId}: HTTP ${resp.code}`);
        return null;
      }
      fs.writeTextSync(jsonPath, resp.body);
      body = resp.body;
    }
    if (body.length === 0) {
      return null;
    }
    const parsed: VersionJson | null = VersionManifest.parseVersionJson(body, versionId);
    if (parsed !== null) {
      this.cache.set(versionId, parsed);
    }
    return parsed;
  }

  public static parseVersionJson(body: string, fallbackId: string): VersionJson | null {
    const root: JsonObj | null = parseJson(body);
    if (root === null) {
      return null;
    }

    const id: string = getStr(root, 'id', fallbackId);
    const type: string = getStr(root, 'type', 'release');
    const mainClass: string = getStr(root, 'mainClass');

    // client jar download
    let client: ClientDownload | null = null;
    const downloads: JsonObj | null = getObj(root, 'downloads');
    if (downloads !== null) {
      const clientObj: JsonObj | null = getObj(downloads, 'client');
      if (clientObj !== null) {
        client = {
          url: getStr(clientObj, 'url'),
          sha1: getStr(clientObj, 'sha1'),
          sizeBytes: getNum(clientObj, 'size')
        };
      }
    }

    // libraries
    const libraries: Array<LibraryEntry> = [];
    const libArr: Array<Object> | null = getArr(root, 'libraries');
    if (libArr !== null) {
      for (const item of libArr) {
        const lib: JsonObj | null = item as JsonObj;
        if (lib === null) {
          continue;
        }
        let download: LibDownload | null = null;
        const dlObj: JsonObj | null = getObj(lib, 'downloads');
        if (dlObj !== null) {
          const art: JsonObj | null = getObj(dlObj, 'artifact');
          if (art !== null) {
            download = {
              coord: getStr(lib, 'name'),
              url: getStr(art, 'url'),
              destPath: '',
              sha1: getStr(art, 'sha1'),
              sizeBytes: getNum(art, 'size')
            };
          }
        }
        let natives: LibNatives | null = null;
        const nativesObj: JsonObj | null = getObj(lib, 'natives');
        if (nativesObj !== null) {
          const classifier: string = getStr(nativesObj, 'linux');
          if (classifier.length > 0) {
            natives = { coord: getStr(lib, 'name'), classifier: classifier };
          }
        }
        const rules: Array<RuleSet> = VersionManifest.parseRules(lib);
        libraries.push({
          name: getStr(lib, 'name'),
          download: download,
          natives: natives,
          rules: rules
        });
      }
    }

    // arguments (modern format)
    const jvmArgs: Array<ArgEntry> = [];
    const gameArgs: Array<ArgEntry> = [];
    const argumentsObj: JsonObj | null = getObj(root, 'arguments');
    if (argumentsObj !== null) {
      const jvmArr: Array<Object> | null = getArr(argumentsObj, 'jvm');
      if (jvmArr !== null) {
        for (const item of jvmArr) {
          const entry: ArgEntry | null = VersionManifest.parseArgEntry(item);
          if (entry !== null) {
            jvmArgs.push(entry);
          }
        }
      }
      const gameArr: Array<Object> | null = getArr(argumentsObj, 'game');
      if (gameArr !== null) {
        for (const item of gameArr) {
          const entry: ArgEntry | null = VersionManifest.parseArgEntry(item);
          if (entry !== null) {
            gameArgs.push(entry);
          }
        }
      }
    }

    // asset index
    let assetIndexId: string = '';
    let assetIndexUrl: string = '';
    const assetIndexObj: JsonObj | null = getObj(root, 'assetIndex');
    if (assetIndexObj !== null) {
      assetIndexId = getStr(assetIndexObj, 'id');
      assetIndexUrl = getStr(assetIndexObj, 'url');
    }

    // java runtime requirement
    let javaMajor: number = 8;
    const javaVersionObj: JsonObj | null = getObj(root, 'javaVersion');
    if (javaVersionObj !== null) {
      javaMajor = getNum(javaVersionObj, 'majorVersion', 8);
    }

    return {
      id: id,
      type: type,
      mainClass: mainClass,
      client: client,
      libraries: libraries,
      jvmArgs: jvmArgs,
      gameArgs: gameArgs,
      legacyMinecraftArguments: getStr(root, 'minecraftArguments'),
      assetIndexId: assetIndexId,
      assetIndexUrl: assetIndexUrl,
      javaMajorVersion: javaMajor
    };
  }

  private static parseArgEntry(item: Object): ArgEntry | null {
    if (typeof item === 'string') {
      return { raw: item as string };
    }
    const obj: JsonObj | null = item as JsonObj;
    if (obj === null) {
      return null;
    }
    const entry: ArgEntry = { rules: VersionManifest.parseRules(obj) };
    const value: Object | undefined = obj['value'];
    if (typeof value === 'string') {
      entry.raw = value as string;
    } else if (Array.isArray(value)) {
      const values: Array<string> = [];
      for (const v of value as Array<Object>) {
        if (typeof v === 'string') {
          values.push(v as string);
        }
      }
      entry.values = values;
    }
    if (entry.raw === undefined && entry.values === undefined) {
      return null;
    }
    return entry;
  }

  private static parseRules(obj: JsonObj): Array<RuleSet> {
    const out: Array<RuleSet> = [];
    const rulesArr: Array<Object> | null = getArr(obj, 'rules');
    if (rulesArr === null) {
      return out;
    }
    for (const item of rulesArr) {
      const rule: JsonObj | null = item as JsonObj;
      if (rule === null) {
        continue;
      }
      const rs: RuleSet = { action: getStr(rule, 'action', 'allow') };
      const os: JsonObj | null = getObj(rule, 'os');
      if (os !== null) {
        rs.osName = getStr(os, 'name');
        rs.osArch = getStr(os, 'arch');
      }
      const features: JsonObj | null = getObj(rule, 'features');
      if (features !== null) {
        rs.features = features;
      }
      out.push(rs);
    }
    return out;
  }
}

export const VersionManifestInstance: VersionManifest = new VersionManifest();
