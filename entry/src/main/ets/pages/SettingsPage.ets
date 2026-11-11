/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import { MicrosoftAuth } from '../auth/MicrosoftAuth';
import { GameLauncherPushBridge } from './HomeTab.ets';
import {
  KEY_RAM_MB, KEY_RESOLUTION_SCALE, KEY_DEMO_MODE, clampRam, maxDeviceRamMb
} from '../common/AppState';

/**
 * Settings: memory, internal render resolution scale, self-test mode,
 * Azure AD client id for the device-code flow, and the control layout
 * editor entry point.
 */

const PREF_NAME: string = 'mc4hos.settings';
const KEY_AZURE_CLIENT_ID: string = 'azureClientId';

@Component
export struct SettingsPage {
  @StorageLink(KEY_RAM_MB) ramMb: number = 2048;
  @StorageLink(KEY_RESOLUTION_SCALE) resolutionScale: number = 100;
  @StorageLink(KEY_DEMO_MODE) selfTestMode: boolean = false;
  @State clientId: string = '';
  @State savedHint: string = '';

  aboutToAppear(): void {
    this.loadClientId();
  }

  private async loadClientId(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const prefs = await preferences.getPreferences(context, { name: PREF_NAME });
    this.clientId = await prefs.get(KEY_AZURE_CLIENT_ID, '') as string;
  }

  private async saveClientId(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const prefs = await preferences.getPreferences(context, { name: PREF_NAME });
    await prefs.put(KEY_AZURE_CLIENT_ID, this.clientId.trim());
    await prefs.flush();
    MicrosoftAuth.configure(this.clientId.trim());
    this.savedHint = this.clientId.trim().length > 0
      ? 'Client id saved.'
      : 'Client id cleared.';
  }

  build() {
    Column() {
      Text('Settings')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Scroll() {
        Column() {
          // Memory
          Row() {
            Text('Memory allocation')
              .fontSize(14)
              .fontColor('#FFFFFF')
            Blank()
            Text(`${this.ramMb} MB`)
              .fontSize(13)
              .fontColor('#63C36A')
          }
          .width('100%')
          Slider({ value: this.ramMb, min: 1024, max: maxDeviceRamMb(), step: 256 })
            .selectedColor('#63C36A')
            .width('100%')
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.ramMb = clampRam(Math.round(value / 256) * 256);
              }
            })

          // Resolution scale
          Row() {
            Text('Internal resolution scale')
              .fontSize(14)
              .fontColor('#FFFFFF')
            Blank()
            Text(`${this.resolutionScale}%`)
              .fontSize(13)
              .fontColor('#5FA8D3')
          }
          .width('100%')
          .margin({ top: 8 })
          Slider({ value: this.resolutionScale, min: 50, max: 150, step: 10 })
            .selectedColor('#5FA8D3')
            .width('100%')
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.resolutionScale = Math.round(value / 10) * 10;
              }
            })

          // Self test
          Row() {
            Column() {
              Text('Native self-test mode')
                .fontSize(14)
                .fontColor('#FFFFFF')
              Text('Run the EGL/GLES surface test instead of the game (no account needed).')
                .fontSize(11)
                .fontColor('#8FA0B3')
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.selfTestMode })
              .selectedColor('#63C36A')
              .onChange((isOn: boolean) => {
                this.selfTestMode = isOn;
              })
          }
          .width('100%')
          .margin({ top: 12 })

          // Azure client id
          Text('Microsoft OAuth client id')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .width('100%')
            .margin({ top: 16 })
          Text('Your own Azure AD application (public client, device-code flow enabled). ' +
            'MC4HOS ships no client id. See docs/BUILD.md §7.')
            .fontSize(11)
            .fontColor('#8FA0B3')
            .width('100%')
            .margin({ top: 2 })
          TextInput({ text: this.clientId, placeholder: '00000000-0000-0000-0000-000000000000' })
            .width('100%')
            .height(40)
            .fontSize(13)
            .backgroundColor('#1F2430')
            .fontColor('#FFFFFF')
            .margin({ top: 6 })
            .onChange((value: string) => {
              this.clientId = value;
            })
          Button('Save client id')
            .height(34)
            .fontSize(12)
            .backgroundColor('#2A3340')
            .margin({ top: 6 })
            .onClick(() => {
              this.saveClientId();
            })
          if (this.savedHint.length > 0) {
            Text(this.savedHint)
              .fontSize(11)
              .fontColor('#63C36A')
              .margin({ top: 4 })
          }

          // Controls editor
          Button('Edit control layout')
            .width('100%')
            .height(44)
            .fontSize(15)
            .backgroundColor('#5FA8D3')
            .margin({ top: 20 })
            .onClick(() => {
              GameLauncherPushBridge.pushControls();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
  }
}
