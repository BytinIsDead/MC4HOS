/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/**
 * Global, UI-bindable launch settings. Values live in AppStorage so any page
 * can read/write them with @StorageLink without a shared singleton instance.
 */

export const KEY_SELECTED_VERSION: string = 'selectedVersionId';
export const KEY_SELECTED_RUNTIME: string = 'selectedRuntimeName';
export const KEY_RAM_MB: string = 'ramMb';
export const KEY_RESOLUTION_SCALE: string = 'resolutionScale';
export const KEY_DEMO_MODE: string = 'selfTestMode';
export const KEY_ACCOUNT_NAME: string = 'accountDisplayName';
export const KEY_ACCOUNT_UUID: string = 'accountUuid';
export const KEY_ACCOUNT_XUID: string = 'accountXuid';
export const KEY_ACCOUNT_READY: string = 'accountReady';

export function maxDeviceRamMb(): number {
  // This SDK's deviceInfo exposes no total-memory field; use a fixed cap
  // that is safe across current HarmonyOS phones/tablets/2-in-1s. The
  // slider clamps into [1024, max], so smaller devices simply won't reach
  // the top of the range.
  return 8192;
}

export function initAppState(): void {
  AppStorage.setOrCreate<string>(KEY_SELECTED_VERSION, '');
  AppStorage.setOrCreate<string>(KEY_SELECTED_RUNTIME, '');
  AppStorage.setOrCreate<number>(KEY_RAM_MB, clampRam(2048));
  AppStorage.setOrCreate<number>(KEY_RESOLUTION_SCALE, 100);
  AppStorage.setOrCreate<boolean>(KEY_DEMO_MODE, false);
  AppStorage.setOrCreate<string>(KEY_ACCOUNT_NAME, '');
  AppStorage.setOrCreate<string>(KEY_ACCOUNT_UUID, '');
  AppStorage.setOrCreate<string>(KEY_ACCOUNT_XUID, '');
  AppStorage.setOrCreate<boolean>(KEY_ACCOUNT_READY, false);
}

export function clampRam(wantedMb: number): number {
  const max: number = maxDeviceRamMb();
  return Math.min(Math.max(1024, wantedMb), max);
}
