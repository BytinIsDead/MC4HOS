/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import { VersionEntry, VersionManifestInstance, VersionJson } from '../download/VersionManifest';
import { GameInstaller } from '../download/GameInstaller';
import { DownloadManager } from '../download/DownloadManager';
import { KEY_SELECTED_VERSION } from '../common/AppState';

/**
 * Version browser: lists official releases/snapshots from the version
 * manifest, shows which ones are installed locally, downloads the selected
 * one (client jar + libraries + assets) and marks it as the launch target.
 */

@Component
export struct VersionsPage {
  @StorageLink(KEY_SELECTED_VERSION) selectedVersion: string = '';
  @State entries: Array<VersionEntry> = [];
  @State installedVersions: Array<string> = [];
  @State filterReleasesOnly: boolean = true;
  @State statusText: string = '';
  @State busy: boolean = false;
  @State progressText: string = '';
  private unsubscribeProgress: (() => void) | null = null;

  aboutToAppear(): void {
    VersionManifestInstance.load().then((entries: Array<VersionEntry>) => {
      this.entries = entries;
      this.refreshInstalled();
    }).catch((err: Error) => {
      this.statusText = `Version list unavailable: ${err.message}`;
    });
    this.unsubscribeProgress = DownloadManager.subscribeProgress(
      (label: string, received: number, total: number,
      finished: boolean, failed: boolean) => {
        if (finished) {
          return;
        }
        const mb: number = Math.round(received / 1048576 * 10) / 10;
        const totalMb: number = total > 0 ? Math.round(total / 1048576 * 10) / 10 : 0;
        this.progressText = totalMb > 0 ? `${label} — ${mb} / ${totalMb} MB` : `${label} — ${mb} MB`;
      });
  }

  aboutToDisappear(): void {
    if (this.unsubscribeProgress !== null) {
      this.unsubscribeProgress();
      this.unsubscribeProgress = null;
    }
  }

  private isInstalled(id: string): boolean {
    return this.installedVersions.indexOf(id) >= 0;
  }

  private refreshInstalled(): void {
    const installed: Array<string> = [];
    for (const entry of this.entries) {
      if (GameInstaller.isInstalled(entry.id)) {
        installed.push(entry.id);
      }
    }
    this.installedVersions = installed;
  }

  private async download(version: VersionEntry): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.statusText = `Resolving ${version.id}…`;
    try {
      const refresh: boolean = GameInstaller.isInstalled(version.id);
      if (refresh) {
        await VersionManifestInstance.load(true);
      }
      const json: VersionJson | null =
        await VersionManifestInstance.fetchVersion(version.id, refresh);
      if (json === null) {
        this.statusText = `Could not resolve ${version.id}`;
        return;
      }
      this.statusText = `Downloading ${version.id}…`;
      const okFiles: boolean = await GameInstaller.ensureInstalled(json,
        (p) => {
          this.progressText = `${p.current} / ${p.total} — ${p.currentFile}`;
        });
      const assets: string = okFiles ? await GameInstaller.ensureAssets(json,
        (p) => {
          this.progressText = `assets ${p.current} / ${p.total}`;
        }) : '';
      if (okFiles && assets.length > 0) {
        GameInstaller.markInstalled(json);
        this.selectedVersion = version.id;
        this.statusText = `${version.id} installed and selected`;
        this.refreshInstalled();
      } else {
        this.statusText = `Download incomplete for ${version.id}`;
        this.refreshInstalled();
      }
    } catch (err) {
      const e = err as Error;
      this.statusText = `Error: ${e.message}`;
    } finally {
      this.busy = false;
      this.progressText = '';
    }
  }

  private typeColor(type: string): string {
    if (type === 'release') {
      return '#63C36A';
    }
    if (type === 'snapshot') {
      return '#D9A94E';
    }
    return '#8FA0B3';
  }

  build() {
    Column() {
      Row() {
        Text('Versions')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
        Blank()
        Toggle({ type: ToggleType.Checkbox, isOn: this.filterReleasesOnly })
          .onChange((isOn: boolean) => {
            this.filterReleasesOnly = isOn;
          })
        Text('releases only')
          .fontSize(11)
          .fontColor('#8FA0B3')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      if (this.statusText.length > 0) {
        Text(this.statusText)
          .fontSize(12)
          .fontColor('#5FA8D3')
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 4 })
      }
      if (this.progressText.length > 0) {
        Text(this.progressText)
          .fontSize(11)
          .fontColor('#8FA0B3')
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 4 })
          .maxLines(1)
      }

      List({ space: 6 }) {
        ForEach(this.entries.filter((e: VersionEntry) =>
          !this.filterReleasesOnly || e.type === 'release'), (entry: VersionEntry) => {
          ListItem() {
            Row() {
              Column() {
                Text(entry.id)
                  .fontSize(15)
                  .fontColor('#FFFFFF')
                Text(`${entry.type} · ${entry.releaseTime.substring(0, 10)}`)
                  .fontSize(11)
                  .fontColor(this.typeColor(entry.type))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              if (this.isInstalled(entry.id)) {
                Text(this.selectedVersion === entry.id ? 'ACTIVE' : 'installed')
                  .fontSize(11)
                  .fontColor(this.selectedVersion === entry.id ? '#63C36A' : '#8FA0B3')
                  .margin({ right: 8 })
              }
              Button(this.isInstalled(entry.id) ? 'Re-fetch' : 'Install')
                .height(32)
                .fontSize(12)
                .backgroundColor('#2A3340')
                .enabled(!this.busy)
                .onClick(() => {
                  this.download(entry);
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .borderRadius(8)
            .backgroundColor('#1F2430')
          }
        }, (entry: VersionEntry) => entry.id)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }
}
