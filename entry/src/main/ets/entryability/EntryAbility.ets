/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import hilog from '@ohos.hilog';
import util from '@ohos.util';
import { Logger } from '../common/Logger';
import { Paths } from '../common/Paths';
import { initAppState } from '../common/AppState';
import { AccountStore } from '../auth/AccountStore';
import { MicrosoftAuth } from '../auth/MicrosoftAuth';
import { ControlLayoutStore } from '../ui/ControlLayout';
import { GameLauncher } from '../launch/GameLauncher';
import { KEY_ACCOUNT_NAME, KEY_ACCOUNT_UUID, KEY_ACCOUNT_XUID, KEY_ACCOUNT_READY, AZURE_CLIENT_ID } from '../common/AppState';

/**
 * Entry ability: wires up the sandbox layout, secure stores, the native log
 * pump and the persisted account state before loading the main page.
 */

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x4D43, 'MC4HOS', 'EntryAbility onCreate');
    Paths.init(this.context);
    Paths.initHapNativeLibraryDir();
    initAppState();
    GameLauncher.bindNative();
    this.initHeapPressureWatch();
    this.initStores();
  }

  /**
   * API 24 ArkTS-VM heap pressure callbacks. Logged so the Console tab shows
   * memory pressure before an OOM kill occurs.
   */
  private initHeapPressureWatch(): void {
    try {
      const registered: boolean = util.ArkTSVM.onVMHeapMemoryPressure(
        (kind: string) => {
          Logger.warn('Memory', `ArkTS heap pressure: ${kind}`);
        },
        { localHeapThreshold: 85, sharedHeapThreshold: 85, processHeapThreshold: 90 });
      if (!registered) {
        Logger.warn('Memory', 'heap pressure callback was not registered');
      }
    } catch (err) {
      const e = err as Error;
      Logger.warn('Memory', `heap pressure watch unavailable: ${e.message}`);
    }
  }

  private async initStores(): Promise<void> {
    await AccountStore.init(this.context);
    await ControlLayoutStore.init(this.context);
    const profile = await AccountStore.loadActiveProfile();
    if (profile !== null) {
      AppStorage.setOrCreate<string>(KEY_ACCOUNT_NAME, profile.displayName);
      AppStorage.setOrCreate<string>(KEY_ACCOUNT_UUID, profile.uuid);
      AppStorage.setOrCreate<string>(KEY_ACCOUNT_XUID, profile.xuid);
      AppStorage.setOrCreate<boolean>(KEY_ACCOUNT_READY, true);
    }
    // The Azure client id is compiled in; there is no user-facing override.
    MicrosoftAuth.configure(AZURE_CLIENT_ID);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code !== 0) {
        hilog.error(0x4D43, 'MC4HOS', 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(0x4D43, 'MC4HOS', 'main page loaded');
    });
  }

  onDestroy(): void {
    hilog.info(0x4D43, 'MC4HOS', 'EntryAbility onDestroy');
  }
}
