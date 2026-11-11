/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/**
 * Data models for the Microsoft / Xbox Live / Minecraft Services
 * authentication chain. All endpoints and field names follow the publicly
 * documented OAuth2 and Microsoft identity-platform protocols.
 */

/** A signed-in account's non-secret identity, persisted in preferences. */
export interface AccountProfile {
  /** Minecraft display name (game profile name). */
  displayName: string;
  /** Minecraft game profile UUID (without dashes as returned by the API). */
  uuid: string;
  /** Xbox user hash from the XSTS ticket. */
  xuid: string;
  /** Epoch milliseconds at which the Minecraft services token expires. */
  mcTokenExpiresAtMs: number;
}

/** Secrets; persisted only in the Asset Store (encrypted secure storage). */
export interface AuthSecrets {
  msAccessToken: string;
  msRefreshToken: string;
  mcAccessToken: string;
}

/** Terminal result of a successful device-code login chain. */
export interface AuthResult {
  profile: AccountProfile;
  secrets: AuthSecrets;
}

/** Device-code flow initiation response (RFC 8628 §3.2). */
export interface DeviceCodeResponse {
  deviceCode: string;
  userCode: string;
  verificationUri: string;
  expiresInSeconds: number;
  pollingIntervalSeconds: number;
}

/** Terminal state of a device-code login attempt. */
export type AuthPhase =
  | 'idle'
  | 'requesting_device_code'
  | 'awaiting_user'
  | 'polling'
  | 'exchanging_xbl'
  | 'fetching_profile'
  | 'done'
  | 'error';

export interface AuthStateUpdate {
  phase: AuthPhase;
  message: string;
}
