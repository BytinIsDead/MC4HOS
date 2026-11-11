/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import { VersionEntry, VersionManifestInstance } from '../download/VersionManifest';
import { GameLauncher, LaunchProgress } from '../launch/GameLauncher';
import {
  KEY_SELECTED_VERSION, KEY_RAM_MB, KEY_ACCOUNT_NAME, KEY_ACCOUNT_READY, KEY_DEMO_MODE,
  clampRam, maxDeviceRamMb
} from '../common/AppState';

/**
 * Main dashboard: account card, version picker, RAM slider, launch progress
 * and the PLAY button. Responsive via GridRow for phone/tablet/foldable.
 */

@Component
export struct HomeTab {
  @StorageLink(KEY_SELECTED_VERSION) selectedVersion: string = '';
  @StorageLink(KEY_RAM_MB) ramMb: number = 2048;
  @StorageLink(KEY_ACCOUNT_NAME) accountName: string = '';
  @StorageLink(KEY_ACCOUNT_READY) accountReady: boolean = false;
  @StorageLink(KEY_DEMO_MODE) selfTestMode: boolean = false;
  @State versions: Array<VersionEntry> = [];
  @State progress: LaunchProgress = { phase: 'idle', message: '' };
  @State launching: boolean = false;
  private navStack: NavPathStack | null = null;

  aboutToAppear(): void {
    this.ramMb = clampRam(this.ramMb);
    VersionManifestInstance.load().then((entries: Array<VersionEntry>) => {
      this.versions = entries.filter((e: VersionEntry) => e.type === 'release');
      if (this.selectedVersion.length === 0 && this.versions.length > 0) {
        this.selectedVersion = this.versions[0].id;
      }
    });
    GameLauncher.onProgress((p: LaunchProgress) => {
      this.progress = p;
      if (p.phase === 'running') {
        this.launching = false;
      } else if (p.phase === 'failed') {
        this.launching = false;
      }
    });
  }

  private async play(): Promise<void> {
    if (this.launching) {
      return;
    }
    this.launching = true;
    // Launch resolves once the JVM thread has been spawned; jump to the game
    // view so the user sees the surface + console immediately.
    const ok: boolean = await GameLauncher.launch(this.selectedVersion);
    if (ok) {
      GameLauncherPushBridge.push();
    } else {
      this.launching = false;
    }
  }

  build() {
    GridRow({ columns: { sm: 4, md: 8, lg: 12 }, gutter: 12 }) {
      GridCol({ span: { sm: 4, md: 8, lg: 12 } }) {
        Column() {
          Text('MC4HOS')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ top: 16 })
        }
      }

      // Account card
      GridCol({ span: { sm: 4, md: 4, lg: 4 } }) {
        Column() {
          Text(this.accountReady ? this.accountName : 'Not signed in')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.accountReady ? '#63C36A' : '#D35F5F')
          Text(this.accountReady ? 'Microsoft account' : 'Add an account in the Accounts tab')
            .fontSize(12)
            .fontColor('#8FA0B3')
            .margin({ top: 4 })
        }
        .width('100%')
        .padding(16)
        .borderRadius(12)
        .backgroundColor('#1F2430')
        .alignItems(HorizontalAlign.Start)
      }

      // Version picker
      GridCol({ span: { sm: 4, md: 4, lg: 4 } }) {
        Column() {
          Text('Version')
            .fontSize(12)
            .fontColor('#8FA0B3')
            .width('100%')
          Select(this.versions.map((e: VersionEntry) => {
            const opt: SelectOption = { value: e.id };
            return opt;
          }))
            .selected(this.selectedVersionIndex())
            .value(this.selectedVersion.length > 0 ? this.selectedVersion : 'Select version')
            .fontColor('#FFFFFF')
            .font({ size: 15 })
            .width('100%')
            .margin({ top: 6 })
            .onSelect((index: number) => {
              if (index >= 0 && index < this.versions.length) {
                this.selectedVersion = this.versions[index].id;
              }
            })
        }
        .width('100%')
        .padding(16)
        .borderRadius(12)
        .backgroundColor('#1F2430')
        .alignItems(HorizontalAlign.Start)
      }

      // RAM slider
      GridCol({ span: { sm: 4, md: 4, lg: 4 } }) {
        Column() {
          Row() {
            Text('Memory')
              .fontSize(12)
              .fontColor('#8FA0B3')
            Blank()
            Text(`${this.ramMb} MB`)
              .fontSize(12)
              .fontColor('#63C36A')
          }
          .width('100%')
          Slider({ value: this.ramMb, min: 1024, max: maxDeviceRamMb(), step: 256 })
            .selectedColor('#63C36A')
            .width('100%')
            .margin({ top: 8 })
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.ramMb = clampRam(Math.round(value / 256) * 256);
              }
            })
        }
        .width('100%')
        .padding(16)
        .borderRadius(12)
        .backgroundColor('#1F2430')
        .alignItems(HorizontalAlign.Start)
      }

      // Launch progress
      GridCol({ span: { sm: 4, md: 8, lg: 12 } }) {
        Column() {
          if (this.progress.phase !== 'idle' && this.progress.message.length > 0) {
            Text(`${this.progress.phase}: ${this.progress.message}`)
              .fontSize(12)
              .fontColor(this.progress.phase === 'failed' ? '#D35F5F' : '#8FA0B3')
              .width('100%')
              .textAlign(TextAlign.Start)
              .maxLines(2)
          }
          Button(this.selfTestMode ? 'RUN SELF-TEST' : 'PLAY')
            .width('100%')
            .height(48)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .backgroundColor(this.launching ? '#3E5A43' : '#63C36A')
            .fontColor('#FFFFFF')
            .margin({ top: 8 })
            .enabled(!this.launching)
            .onClick(() => {
              this.play();
            })
          Button('Open game view')
            .width('100%')
            .height(36)
            .fontSize(13)
            .backgroundColor('#2A3340')
            .fontColor('#8FA0B3')
            .margin({ top: 8 })
            .onClick(() => {
              this.pushGameView();
            })
        }
        .width('100%')
        .margin({ top: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, bottom: 16 })
    .scrollable(ScrollDirection.Vertical)
    .alignItems(GridRowAlignItems.Start)
  }

  private selectedVersionIndex(): number {
    for (let i = 0; i < this.versions.length; i++) {
      if (this.versions[i].id === this.selectedVersion) {
        return i;
      }
    }
    return -1;
  }

  private pushGameView(): void {
    // HomeTab is embedded directly in the Navigation root, so the provided
    // stack is reachable through the global AppStorage bridge set by Index.
    GameLauncherPushBridge.push();
  }
}

/**
 * Minimal bridge so embedded tabs can navigate the parent Navigation stack
 * without prop-drilling the NavPathStack through every component.
 */
export class GameLauncherPushBridge {
  private static stack: NavPathStack | null = null;

  public static bind(stack: NavPathStack): void {
    GameLauncherPushBridge.stack = stack;
  }

  public static push(): void {
    if (GameLauncherPushBridge.stack !== null) {
      GameLauncherPushBridge.stack.pushPathByName('game', null);
    }
  }

  public static pushControls(): void {
    if (GameLauncherPushBridge.stack !== null) {
      GameLauncherPushBridge.stack.pushPathByName('controls', null);
    }
  }

  public static pop(): void {
    if (GameLauncherPushBridge.stack !== null) {
      GameLauncherPushBridge.stack.pop();
    }
  }
}
