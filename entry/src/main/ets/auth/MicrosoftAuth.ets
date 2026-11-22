/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import { getJson, postJson, postForm } from '../common/Http';
import { JsonObj, parseJson, getStr, getNum, getArr, getObj } from '../common/JsonReader';
import { Logger } from '../common/Logger';
import { oauthErrorMessage, xboxErrorMessage } from '../core/auth/AuthErrors';
import { AccountProfile, AuthSecrets, DeviceCodeResponse, DeviceFlowStart, AuthStateUpdate, AuthResult, AuthPhase, TicketProperties } from './AuthModels';

/**
 * Microsoft account sign-in via the OAuth 2.0 Device Authorization Grant
 * (RFC 8628) followed by the publicly documented Xbox Live (XBL/XSTS) and
 * Minecraft services ticket exchanges.
 *
 * The Azure application (public client) id is compiled into the app
 * (`AZURE_CLIENT_ID`) and configured once at startup. The registration must
 * allow personal Microsoft accounts and public client flows; the scope is
 * `XboxLive.signin offline_access`. See docs/BUILD.md §7.
 */

const TAG: string = 'Auth';

const MS_DEVICE_CODE_URL: string =
  'https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode';
const MS_TOKEN_URL: string =
  'https://login.microsoftonline.com/consumers/oauth2/v2.0/token';
const MS_SCOPE: string = 'XboxLive.signin offline_access';

const XBL_AUTH_URL: string = 'https://user.auth.xboxlive.com/user/authenticate';
const XSTS_AUTH_URL: string = 'https://xsts.auth.xboxlive.com/xsts/authorize';
const MC_LOGIN_URL: string = 'https://api.minecraftservices.com/authentication/login_with_xbox';
const MC_PROFILE_URL: string = 'https://api.minecraftservices.com/minecraft/profile';

/** XBL/XSTS reply; `body`/`code` are kept so failures can be explained. */
interface TicketResponse {
  json: JsonObj | null;
  body: string;
  code: number;
}

export class MicrosoftAuth {
  private static clientId: string = '';

  public static configure(clientId: string): void {
    MicrosoftAuth.clientId = clientId.trim();
  }

  /** RFC 8628 step 1: obtain device_code + user_code for the user to enter. */
  public static async beginDeviceFlow(): Promise<DeviceFlowStart> {
    if (MicrosoftAuth.clientId.length === 0) {
      Logger.error(TAG, 'client id not configured; call MicrosoftAuth.configure() first');
      return {
        device: null,
        error: 'No Azure client id is configured. See docs/BUILD.md §7.'
      };
    }
    const body: string =
      `client_id=${encodeURIComponent(MicrosoftAuth.clientId)}` +
      `&scope=${encodeURIComponent(MS_SCOPE)}`;
    const resp = await postForm(MS_DEVICE_CODE_URL, body);
    if (!resp.ok) {
      const error: string = MicrosoftAuth.requestFailure(resp.code, resp.body);
      Logger.error(TAG, `device code request failed: HTTP ${resp.code} ${resp.body}`);
      return { device: null, error: error };
    }
    const json: JsonObj | null = parseJson(resp.body);
    if (json === null) {
      return { device: null, error: 'Microsoft returned an unreadable device-code response.' };
    }
    const device: DeviceCodeResponse = {
      deviceCode: getStr(json, 'device_code'),
      userCode: getStr(json, 'user_code'),
      verificationUri: getStr(json, 'verification_uri'),
      expiresInSeconds: getNum(json, 'expires_in', 900),
      pollingIntervalSeconds: getNum(json, 'interval', 5)
    };
    if (device.deviceCode.length === 0 || device.userCode.length === 0) {
      return { device: null, error: 'Microsoft returned an incomplete device code.' };
    }
    return { device: device, error: '' };
  }

  /** Turns transport/OAuth failures into messages suitable for the UI. */
  private static requestFailure(code: number, body: string): string {
    if (code === -1) {
      return 'Network error: could not reach login.microsoftonline.com. ' +
        'Check the connection and retry.';
    }
    return oauthErrorMessage(body, `Microsoft rejected the request (HTTP ${code}).`);
  }

  /**
   * RFC 8628 steps 2-4: poll the token endpoint until the user approves,
   * then walk the XBL → XSTS → Minecraft ticket chain. Reports progress via
   * `onUpdate` and resolves with the complete account, or null on failure.
   */
  public static async pollAndAuthorize(
    device: DeviceCodeResponse,
    onUpdate?: (update: AuthStateUpdate) => void
  ): Promise<AuthResult | null> {
    const report = (phase: string, message: string): void => {
      Logger.info(TAG, `[${phase}] ${message}`);
      if (onUpdate !== undefined) {
        onUpdate({ phase: phase as AuthPhase, message: message });
      }
    };

    // --- OAuth token polling loop ---
    report('awaiting_user',
      `Open ${device.verificationUri} and enter code ${device.userCode}`);
    const deadline: number = Date.now() + device.expiresInSeconds * 1000;
    let msAccessToken: string = '';
    let msRefreshToken: string = '';
    let intervalMs: number = device.pollingIntervalSeconds * 1000;

    while (Date.now() < deadline) {
      await sleep(intervalMs);
      report('polling', 'Waiting for authorization…');
      const body: string =
        `grant_type=${encodeURIComponent('urn:ietf:params:oauth:grant-type:device_code')}` +
        `&client_id=${encodeURIComponent(MicrosoftAuth.clientId)}` +
        `&device_code=${encodeURIComponent(device.deviceCode)}`;
      const resp = await postForm(MS_TOKEN_URL, body);
      if (resp.code === -1) {
        report('error', MicrosoftAuth.requestFailure(resp.code, resp.body));
        return null;
      }
      const json: JsonObj | null = parseJson(resp.body);
      if (json === null) {
        report('error', 'Malformed token response');
        return null;
      }
      const err: string = getStr(json, 'error');
      if (err === 'authorization_pending') {
        continue;
      }
      if (err === 'slow_down') {
        intervalMs += 5000;
        continue;
      }
      if (err.length > 0) {
        report('error', oauthErrorMessage(resp.body, `Authorization failed: ${err}`));
        return null;
      }
      msAccessToken = getStr(json, 'access_token');
      msRefreshToken = getStr(json, 'refresh_token');
      if (msAccessToken.length === 0) {
        report('error', 'Token response missing access_token');
        return null;
      }
      break;
    }
    if (msAccessToken.length === 0) {
      report('error', 'Device code expired before authorization completed');
      return null;
    }

    // --- XBL user token ---
    report('exchanging_xbl', 'Requesting Xbox Live token…');
    const xblProps: TicketProperties = {
      AuthMethod: 'RPS',
      SiteName: 'user.auth.xboxlive.com',
      RpsTicket: `d=${msAccessToken}`
    };
    const xbl = await MicrosoftAuth.xblRequest(
      XBL_AUTH_URL, xblProps, 'http://auth.xboxlive.com');
    if (xbl.json === null) {
      const reason: string = xboxErrorMessage(xbl.body);
      report('error', reason.length > 0
        ? reason
        : `Xbox Live authentication failed (HTTP ${xbl.code}).`);
      return null;
    }
    const xblToken: string = getStr(xbl.json, 'Token');
    const xblUhs: string = MicrosoftAuth.firstUserHash(xbl.json);

    // --- XSTS token (Minecraft relying party) ---
    report('exchanging_xbl', 'Requesting XSTS ticket…');
    const xstsProps: TicketProperties = {
      SandboxId: 'RETAIL',
      UserTokens: [xblToken]
    };
    const xsts = await MicrosoftAuth.xblRequest(
      XSTS_AUTH_URL, xstsProps, 'rp://api.minecraftservices.com/');
    if (xsts.json === null) {
      const reason: string = xboxErrorMessage(xsts.body);
      report('error', reason.length > 0
        ? reason
        : `XSTS authorization failed (HTTP ${xsts.code}; is this an Xbox account?)`);
      return null;
    }
    const xstsToken: string = getStr(xsts.json, 'Token');
    const xstsUhs: string = MicrosoftAuth.firstUserHash(xsts.json);
    const uhs: string = xstsUhs.length > 0 ? xstsUhs : xblUhs;

    // --- Minecraft services access token ---
    report('exchanging_xbl', 'Signing in to Minecraft services…');
    const loginPayload: Record<string, string> = {};
    loginPayload['identityToken'] = `XBL3.0 x=${uhs};${xstsToken}`;
    const acceptHeaders: Record<string, string> = {};
    acceptHeaders['Accept'] = 'application/json';
    const mcResp = await postJson(MC_LOGIN_URL,
      JSON.stringify(loginPayload), acceptHeaders);
    if (!mcResp.ok) {
      Logger.warn(TAG, `Minecraft login failed: HTTP ${mcResp.code} ${mcResp.body}`);
      let hint: string = '';
      if (mcResp.body.indexOf('Invalid app registration') >= 0) {
        hint = ' — this Azure app is not approved for the Minecraft API; ' +
          'request access at https://aka.ms/AppRegInfo';
      } else if (mcResp.code === 401) {
        hint = ' — the account may not own Minecraft: Java Edition';
      }
      report('error', `Minecraft login failed: HTTP ${mcResp.code}${hint}`);
      return null;
    }
    const mcJson: JsonObj | null = parseJson(mcResp.body);
    if (mcJson === null) {
      return null;
    }
    const mcToken: string = getStr(mcJson, 'access_token');
    const mcExpiresIn: number = getNum(mcJson, 'expires_in', 86400);

    // --- Game profile ---
    report('fetching_profile', 'Fetching profile…');
    const profileResp = await getJson(MC_PROFILE_URL,
      { 'Authorization': `Bearer ${mcToken}` });
    if (!profileResp.ok) {
      report('error', `Profile fetch failed: HTTP ${profileResp.code} (no Minecraft license on this account?)`);
      return null;
    }
    const profileJson: JsonObj | null = parseJson(profileResp.body);
    if (profileJson === null) {
      report('error', 'Malformed profile response');
      return null;
    }

    const profile: AccountProfile = {
      displayName: getStr(profileJson, 'name'),
      uuid: getStr(profileJson, 'id'),
      xuid: uhs,
      mcTokenExpiresAtMs: Date.now() + mcExpiresIn * 1000
    };
    const secrets: AuthSecrets = {
      msAccessToken: msAccessToken,
      msRefreshToken: msRefreshToken,
      mcAccessToken: mcToken
    };
    report('done', `Signed in as ${profile.displayName}`);
    return { profile: profile, secrets: secrets };
  }

  /** Refresh the Microsoft tokens using the stored refresh_token grant. */
  public static async refreshTokens(refreshToken: string): Promise<AuthSecrets | null> {
    const body: string =
      `grant_type=refresh_token` +
      `&client_id=${encodeURIComponent(MicrosoftAuth.clientId)}` +
      `&refresh_token=${encodeURIComponent(refreshToken)}` +
      `&scope=${encodeURIComponent(MS_SCOPE)}`;
    const resp = await postForm(MS_TOKEN_URL, body);
    const json: JsonObj | null = parseJson(resp.body);
    if (json === null || !resp.ok) {
      Logger.warn(TAG, `token refresh failed: HTTP ${resp.code}`);
      return null;
    }
    const newAccess: string = getStr(json, 'access_token');
    const newRefresh: string = getStr(json, 'refresh_token', refreshToken);
    if (newAccess.length === 0) {
      return null;
    }
    // Refresh the Minecraft services token as well.
    const xblProps: TicketProperties = {
      AuthMethod: 'RPS',
      SiteName: 'user.auth.xboxlive.com',
      RpsTicket: `d=${newAccess}`
    };
    const xbl: TicketResponse =
      await MicrosoftAuth.xblRequest(XBL_AUTH_URL, xblProps, 'http://auth.xboxlive.com');
    if (xbl.json === null) {
      return null;
    }
    const xstsProps: TicketProperties = {
      SandboxId: 'RETAIL',
      UserTokens: [getStr(xbl.json, 'Token')]
    };
    const xsts: TicketResponse = await MicrosoftAuth.xblRequest(
      XSTS_AUTH_URL, xstsProps, 'rp://api.minecraftservices.com/');
    if (xsts.json === null) {
      return null;
    }
    let uhs: string = MicrosoftAuth.firstUserHash(xsts.json);
    if (uhs.length === 0) {
      uhs = MicrosoftAuth.firstUserHash(xbl.json);
    }
    if (uhs.length === 0) {
      Logger.warn(TAG, 'refresh: no user hash in XBL/XSTS response');
      return null;
    }
    const loginPayload: Record<string, string> = {};
    loginPayload['identityToken'] = `XBL3.0 x=${uhs};${getStr(xsts.json, 'Token')}`;
    const acceptHeaders: Record<string, string> = {};
    acceptHeaders['Accept'] = 'application/json';
    const mcResp = await postJson(MC_LOGIN_URL,
      JSON.stringify(loginPayload), acceptHeaders);
    if (!mcResp.ok) {
      return null;
    }
    const mcJson: JsonObj | null = parseJson(mcResp.body);
    if (mcJson === null) {
      return null;
    }
    return {
      msAccessToken: newAccess,
      msRefreshToken: newRefresh,
      mcAccessToken: getStr(mcJson, 'access_token')
    };
  }

  /**
   * Standard XBL/XSTS POST envelope. Xbox Live answers malformed envelopes
   * with an empty HTTP 400, so the body must match the published schema:
   * Properties + RelyingParty + TokenType, plus the contract-version header.
   */
  private static async xblRequest(
    url: string,
    properties: TicketProperties,
    relyingParty: string
  ): Promise<TicketResponse> {
    const payload: Record<string, Object> = {};
    payload['Properties'] = properties;
    payload['RelyingParty'] = relyingParty;
    payload['TokenType'] = 'JWT';
    const headers: Record<string, string> = {};
    headers['Accept'] = 'application/json';
    headers['x-xbl-contract-version'] = '1';
    const resp = await postJson(url, JSON.stringify(payload), headers);
    if (!resp.ok) {
      Logger.warn(TAG, `xbl request ${url} failed: HTTP ${resp.code} ${resp.body}`);
      return { json: null, body: resp.body, code: resp.code };
    }
    return { json: parseJson(resp.body), body: resp.body, code: resp.code };
  }

  private static firstUserHash(json: JsonObj): string {
    const claims: JsonObj | null = getObj(json, 'DisplayClaims');
    if (claims === null) {
      return '';
    }
    const items: Array<Object> | null = getArr(claims, 'xui');
    if (items === null || items.length === 0) {
      return '';
    }
    const first = items[0] as JsonObj;
    return getStr(first, 'uhs');
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
}
