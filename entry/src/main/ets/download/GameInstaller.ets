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
import { JsonObj, parseJson, getStr, getNum, getObj } from '../common/JsonReader';
import { Logger } from '../common/Logger';
import { Paths } from '../common/Paths';
import { DownloadSpec } from './DownloadTask';
import { DownloadBatchResult, DownloadManagerInstance } from './DownloadManager';
import { VersionJson, DEFAULT_ASSETS_BASE } from './VersionManifest';

/**
 * Materializes a fully playable version tree: client jar, dependency
 * libraries (maven layout), asset index and hashed asset objects.
 *
 * Native libraries (LWJGL, OpenAL, GL translation) are NOT downloaded from
 * Mojang — they are OpenHarmony ARM64 builds deployed under
 * Paths.nativesVersionDir() by the runtime pack pipeline (see docs/NATIVES.md).
 */

const TAG: string = 'GameInstaller';

export interface InstallProgress {
  current: number;
  total: number;
  currentFile: string;
}

export class GameInstaller {
  /**
   * Ensures every file required to launch `version` exists locally and
   * passes checksum verification. Idempotent and resumable.
   */
  public static async ensureInstalled(version: VersionJson,
    onProgress?: (progress: InstallProgress) => void): Promise<boolean> {
    const specs: Array<DownloadSpec> = GameInstaller.buildSpecs(version);
    Logger.info(TAG, `install ${version.id}: ${specs.length} files to verify/download`);
    if (specs.length === 0) {
      return true;
    }
    let finished: number = 0;
    const result: DownloadBatchResult = await DownloadManagerInstance.downloadAll(specs, {
      onItemFinished: (r) => {
        finished++;
        if (onProgress !== undefined) {
          onProgress({
            current: finished,
            total: specs.length,
            currentFile: r.spec.label ?? r.spec.destPath
          });
        }
      }
    });
    if (result.failed.length > 0) {
      for (const f of result.failed) {
        Logger.error(TAG, `install failed for ${f.spec.destPath}: ${f.error ?? 'unknown'}`);
      }
      return false;
    }
    return true;
  }

  /** Computes the complete download plan for a version. */
  public static buildSpecs(version: VersionJson): Array<DownloadSpec> {
    const specs: Array<DownloadSpec> = [];

    // 1. client jar
    if (version.client !== null && version.client.url.length > 0) {
      specs.push({
        url: version.client.url,
        destPath: Paths.clientJarPath(version.id),
        sha1: version.client.sha1,
        sizeBytes: version.client.sizeBytes,
        label: `${version.id}.jar`
      });
    }

    // 2. libraries — artifact jars only. Libraries whose rules exclude our
    //    platform are filtered by the same rule engine used at launch time
    //    (imported here to keep selection logic in one place).
    for (const lib of version.libraries) {
      if (!GameInstaller.rulesAllow(lib.rules)) {
        continue;
      }
      if (lib.download === null || lib.download.url.length === 0) {
        continue;
      }
      const coordParts: Array<string> = lib.download.coord.split(':');
      if (coordParts.length !== 3) {
        continue;
      }
      const dest: string = Paths.libraryPath(coordParts[0], coordParts[1], coordParts[2]);
      specs.push({
        url: lib.download.url,
        destPath: dest,
        sha1: lib.download.sha1,
        sizeBytes: lib.download.sizeBytes,
        label: coordParts[1] + '-' + coordParts[2] + '.jar'
      });
    }

    return specs;
  }

  /**
   * Ensures the asset index and all asset objects referenced by it are on
   * disk. Returns the asset index id (used by the JVM arg builder), or ''
   * on failure.
   */
  public static async ensureAssets(version: VersionJson,
    onProgress?: (progress: InstallProgress) => void): Promise<string> {
    if (version.assetIndexId.length === 0) {
      return '';
    }
    const indexPath: string = Paths.assetIndexPath(version.assetIndexId);
    if (!fsAccess(indexPath)) {
      const base: string = version.assetIndexUrl.length > 0
        ? version.assetIndexUrl
        : 'https://piston-meta.mojang.com/v1/packages/';
      // assetIndex.url ends with '/' and the descriptor id is appended.
      const resp = await getJson(`${base}${version.assetIndexId}.json`);
      if (!resp.ok) {
        Logger.error(TAG, `asset index fetch failed: HTTP ${resp.code}`);
        return '';
      }
      Paths.ensureDir(Paths.indexesDir());
      fsWriteText(indexPath, resp.body);
    }

    const root: JsonObj | null = parseJson(fsReadText(indexPath));
    if (root === null) {
      return '';
    }
    const objects: JsonObj | null = getObj(root, 'objects');
    if (objects === null) {
      return '';
    }

    const specs: Array<DownloadSpec> = [];
    for (const key of Object.keys(objects)) {
      const entry: JsonObj | null = getObj(objects, key);
      if (entry === null) {
        continue;
      }
      const hash: string = getStr(entry, 'hash');
      const size: number = getNum(entry, 'size');
      if (hash.length !== 40) {
        continue;
      }
      specs.push({
        url: `${DEFAULT_ASSETS_BASE}/${hash.substring(0, 2)}/${hash}`,
        destPath: Paths.assetObjectPath(hash),
        sha1: hash,
        sizeBytes: size,
        label: key
      });
    }
    Logger.info(TAG, `assets: ${specs.length} objects for index ${version.assetIndexId}`);

    if (specs.length > 0) {
      let finished: number = 0;
      const result: DownloadBatchResult = await DownloadManagerInstance.downloadAll(specs, {
        onItemFinished: (r) => {
          finished++;
          if (onProgress !== undefined) {
            onProgress({
              current: finished,
              total: specs.length,
              currentFile: r.spec.label ?? ''
            });
          }
        }
      });
      if (result.failed.length > 0) {
        Logger.error(TAG, `${result.failed.length} asset objects failed`);
      }
    }
    return version.assetIndexId;
  }

  /**
   * Rule evaluation used for downloads. The launcher maps its POSIX runtime
   * onto the "linux" OS family; arm64/x86_64 are both treated as 64-bit.
   */
  public static rulesAllow(rules: Array<{ action: string, osName?: string, osArch?: string,
    features?: JsonObj }>): boolean {
    let allowed: boolean = true;
    for (const rule of rules) {
      const featureKeys: Array<string> = rule.features !== undefined ? Object.keys(rule.features) : [];
      if (featureKeys.length > 0) {
        // Feature rules are evaluated at launch time by the JVM argument
        // builder (resolution, demo mode). For downloads, features never
        // pull additional jars, so feature-gated rules are ignored here.
        continue;
      }
      let matches: boolean = true;
      if (rule.osName !== undefined && rule.osName.length > 0) {
        matches = matches && rule.osName === 'linux';
      }
      if (rule.osArch !== undefined && rule.osArch.length > 0) {
        matches = matches && (rule.osArch === 'arm64' || rule.osArch === 'x86_64');
      }
      if (matches) {
        allowed = rule.action === 'allow';
      }
    }
    return allowed;
  }
}

// Small fs helpers kept out of the class for clarity.
function fsAccess(path: string): boolean {
  try {
    return fs.accessSync(path);
  } catch (err) {
    return false;
  }
}

function fsReadText(path: string): string {
  return fs.readTextSync(path);
}

function fsWriteText(path: string, text: string): void {
  fs.writeTextSync(path, text);
}
