/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import { MicrosoftAuth } from '../auth/MicrosoftAuth';
import { AccountStore } from '../auth/AccountStore';
import { DeviceCodeResponse, AuthStateUpdate } from '../auth/AuthModels';
import {
  KEY_ACCOUNT_NAME, KEY_ACCOUNT_UUID, KEY_ACCOUNT_XUID, KEY_ACCOUNT_READY
} from '../common/AppState';
import { Logger } from '../common/Logger';

/**
 * Microsoft account management: OAuth2 device-code sign-in (user visits the
 * verification URL and enters the shown code on another device) and sign-out.
 */

@Component
export struct AccountsPage {
  @StorageLink(KEY_ACCOUNT_NAME) accountName: string = '';
  @StorageLink(KEY_ACCOUNT_UUID) accountUuid: string = '';
  @StorageLink(KEY_ACCOUNT_XUID) accountXuid: string = '';
  @StorageLink(KEY_ACCOUNT_READY) accountReady: boolean = false;
  @State authMessage: string = '';
  @State authBusy: boolean = false;
  @State userCode: string = '';
  @State verificationUri: string = '';

  private async signIn(): Promise<void> {
    if (this.authBusy) {
      return;
    }
    this.authBusy = true;
    this.authMessage = 'Requesting device code…';
    this.userCode = '';
    this.verificationUri = '';
    try {
      const device: DeviceCodeResponse | null = await MicrosoftAuth.beginDeviceFlow();
      if (device === null) {
        this.authMessage = 'Device code request failed. Configure an Azure client id in Settings.';
        this.authBusy = false;
        return;
      }
      this.userCode = device.userCode;
      this.verificationUri = device.verificationUri;
      const result = await MicrosoftAuth.pollAndAuthorize(device,
        (update: AuthStateUpdate) => {
          this.authMessage = update.message;
        });
      if (result === null) {
        this.authMessage = 'Sign-in did not complete.';
        this.authBusy = false;
        return;
      }
      await AccountStore.saveActiveAccount(result.profile, result.secrets);
      this.accountName = result.profile.displayName;
      this.accountUuid = result.profile.uuid;
      this.accountXuid = result.profile.xuid;
      this.accountReady = true;
      this.authMessage = `Signed in as ${result.profile.displayName}`;
    } catch (err) {
      const e = err as Error;
      Logger.error('AccountsPage', `sign-in error: ${e.message}`);
      this.authMessage = `Sign-in error: ${e.message}`;
    }
    this.authBusy = false;
  }

  private async signOut(): Promise<void> {
    await AccountStore.signOut();
    this.accountName = '';
    this.accountUuid = '';
    this.accountXuid = '';
    this.accountReady = false;
    this.authMessage = 'Signed out.';
  }

  build() {
    Column() {
      Text('Accounts')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Column() {
        Text(this.accountReady ? this.accountName : 'No account')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.accountReady ? '#63C36A' : '#8FA0B3')
        if (this.accountReady) {
          Text(`uuid: ${this.accountUuid}`)
            .fontSize(11)
            .fontColor('#8FA0B3')
            .margin({ top: 4 })
          Text(`xuid: ${this.accountXuid}`)
            .fontSize(11)
            .fontColor('#8FA0B3')
        }
        if (!this.accountReady) {
          Button('Sign in with Microsoft')
            .width('100%')
            .height(44)
            .fontSize(15)
            .backgroundColor('#5FA8D3')
            .margin({ top: 12 })
            .enabled(!this.authBusy)
            .onClick(() => {
              this.signIn();
            })
        } else {
          Button('Sign out')
            .width('100%')
            .height(44)
            .fontSize(15)
            .backgroundColor('#B33A3A')
            .margin({ top: 12 })
            .onClick(() => {
              this.signOut();
            })
        }

        if (this.verificationUri.length > 0) {
          Column() {
            Text('On any browser, open:')
              .fontSize(12)
              .fontColor('#8FA0B3')
            Text(this.verificationUri)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor('#5FA8D3')
              .margin({ top: 4 })
            Text('Then enter the code:')
              .fontSize(12)
              .fontColor('#8FA0B3')
              .margin({ top: 8 })
            Text(this.userCode)
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .letterSpacing(3)
              .margin({ top: 4 })
          }
          .width('100%')
          .padding(12)
          .borderRadius(8)
          .backgroundColor('#14181F')
          .margin({ top: 12 })
        }

        if (this.authMessage.length > 0) {
          Text(this.authMessage)
            .fontSize(12)
            .fontColor('#D9A94E')
            .margin({ top: 8 })
            .width('100%')
        }
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
