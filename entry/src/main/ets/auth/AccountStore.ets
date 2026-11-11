/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import preferences from '@ohos.data.preferences';
import asset from '@ohos.security.asset';
import common from '@ohos.app.ability.common';
import { Logger } from '../common/Logger';
import { MicrosoftAuth } from './MicrosoftAuth';
import { AccountProfile, AuthSecrets } from './AuthModels';

/**
 * Account persistence.
 *
 *  - Non-secret identity (display name, uuid, xuid, expiry) lives in
 *    Preferences (`mc4hos.accounts`).
 *  - Secrets (Microsoft access/refresh tokens, Minecraft services token)
 *    live exclusively in the Asset Store Kit, which is backed by hardware
 *    keystores (TEE/HUKS). They are never written to preferences or logs.
 */

const TAG: string = 'AccountStore';
const PREF_NAME: string = 'mc4hos.accounts';
const PREF_KEY_PROFILE: string = 'activeProfile';
const ASSET_ALIAS_MS_ACCESS: string = 'mc4hos.ms.access';
const ASSET_ALIAS_MS_REFRESH: string = 'mc4hos.ms.refresh';
const ASSET_ALIAS_MC_TOKEN: string = 'mc4hos.mc.token';

export class AccountStore {
  private static prefs: preferences.Preferences | null = null;

  public static async init(context: common.UIAbilityContext): Promise<void> {
    AccountStore.prefs =
      await preferences.getPreferences(context, { name: PREF_NAME });
    Logger.info(TAG, 'account store ready');
  }

  /** Persist profile + secrets for the active account. */
  public static async saveActiveAccount(profile: AccountProfile, secrets: AuthSecrets): Promise<void> {
    if (AccountStore.prefs === null) {
      return;
    }
    await AccountStore.prefs.put(PREF_KEY_PROFILE, JSON.stringify(profile));
    await AccountStore.prefs.flush();
    await assetSetString(ASSET_ALIAS_MS_ACCESS, secrets.msAccessToken);
    await assetSetString(ASSET_ALIAS_MS_REFRESH, secrets.msRefreshToken);
    await assetSetString(ASSET_ALIAS_MC_TOKEN, secrets.mcAccessToken);
    Logger.info(TAG, `saved account ${profile.displayName}`);
  }

  /** Load the active profile, or null when signed out. */
  public static async loadActiveProfile(): Promise<AccountProfile | null> {
    if (AccountStore.prefs === null) {
      return null;
    }
    const raw: string = await AccountStore.prefs.get(PREF_KEY_PROFILE, '') as string;
    if (raw.length === 0) {
      return null;
    }
    try {
      return JSON.parse(raw) as AccountProfile;
    } catch (err) {
      return null;
    }
  }

  /** Secrets for the active account; null if any component is missing. */
  public static async loadSecrets(): Promise<AuthSecrets | null> {
    const msAccess: string = await assetGetString(ASSET_ALIAS_MS_ACCESS);
    const msRefresh: string = await assetGetString(ASSET_ALIAS_MS_REFRESH);
    const mcToken: string = await assetGetString(ASSET_ALIAS_MC_TOKEN);
    if (msRefresh.length === 0) {
      return null;
    }
    return {
      msAccessToken: msAccess,
      msRefreshToken: msRefresh,
      mcAccessToken: mcToken
    };
  }

  /**
   * Returns a valid Minecraft services token, transparently refreshing the
   * Microsoft session when the stored one is within 5 minutes of expiry.
   */
  public static async ensureValidMcToken(): Promise<string | null> {
    const profile: AccountProfile | null = await AccountStore.loadActiveProfile();
    const secrets: AuthSecrets | null = await AccountStore.loadSecrets();
    if (profile === null || secrets === null) {
      return null;
    }
    if (secrets.mcAccessToken.length > 0 && Date.now() < profile.mcTokenExpiresAtMs - 300000) {
      return secrets.mcAccessToken;
    }
    Logger.info(TAG, 'refreshing Minecraft services token');
    const refreshed: AuthSecrets | null = await MicrosoftAuth.refreshTokens(secrets.msRefreshToken);
    if (refreshed === null) {
      Logger.warn(TAG, 'token refresh failed; re-authentication required');
      return null;
    }
    const updated: AccountProfile = {
      displayName: profile.displayName,
      uuid: profile.uuid,
      xuid: profile.xuid,
      mcTokenExpiresAtMs: Date.now() + 86400 * 1000
    };
    await AccountStore.saveActiveAccount(updated, refreshed);
    return refreshed.mcAccessToken;
  }

  /** Sign out: wipes profile and all secure tokens. */
  public static async signOut(): Promise<void> {
    await assetRemove(ASSET_ALIAS_MS_ACCESS);
    await assetRemove(ASSET_ALIAS_MS_REFRESH);
    await assetRemove(ASSET_ALIAS_MC_TOKEN);
    if (AccountStore.prefs !== null) {
      await AccountStore.prefs.delete(PREF_KEY_PROFILE);
      await AccountStore.prefs.flush();
    }
    Logger.info(TAG, 'signed out');
  }
}

// ---------------------------------------------------------------------------
// Asset Store Kit helpers (Map<asset.Tag, Uint8Array | boolean | number>)
// ---------------------------------------------------------------------------

function strToU8(s: string): Uint8Array {
  const out: Uint8Array = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) {
    out[i] = s.charCodeAt(i) & 0xFF;
  }
  return out;
}

function u8ToStr(u: Uint8Array): string {
  let s: string = '';
  for (let i = 0; i < u.length; i++) {
    s += String.fromCharCode(u[i]);
  }
  return s;
}

async function assetSetString(alias: string, value: string): Promise<void> {
  try {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, strToU8(alias));
    // Update if present, otherwise add.
    const existing: asset.AssetMap = new Map();
    existing.set(asset.Tag.ALIAS, strToU8(alias));
    existing.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      await asset.get(existing);
      const update: asset.AssetMap = new Map();
      update.set(asset.Tag.ALIAS, strToU8(alias));
      update.set(asset.Tag.SECRET, strToU8(value));
      await asset.update(update);
      return;
    } catch (notFoundErr) {
      // fall through to add
    }
    const add: asset.AssetMap = new Map();
    add.set(asset.Tag.ALIAS, strToU8(alias));
    add.set(asset.Tag.SECRET, strToU8(value));
    add.set(asset.Tag.SYNC_TYPE, asset.SyncType.DEVICE_SYNC_OK);
    await asset.add(add);
  } catch (err) {
    const e = err as Error;
    Logger.warn(TAG, `asset set ${alias} failed: ${e.message}`);
  }
}

async function assetGetString(alias: string): Promise<string> {
  try {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, strToU8(alias));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    const result: asset.AssetMap = await asset.get(query);
    const secret: Uint8Array | boolean | number | undefined = result.get(asset.Tag.SECRET);
    if (secret === undefined || typeof secret !== 'object') {
      return '';
    }
    return u8ToStr(secret as Uint8Array);
  } catch (err) {
    return '';
  }
}

async function assetRemove(alias: string): Promise<void> {
  try {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, strToU8(alias));
    await asset.remove(query);
  } catch (err) {
    // absent alias is fine
  }
}
