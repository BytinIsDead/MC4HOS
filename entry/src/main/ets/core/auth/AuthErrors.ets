/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Turns Microsoft identity and Xbox Live error payloads into short,
 * actionable messages. Pure string/JSON helpers so they run under Node.
 */

import { parseJson, getStr, getNum } from '../../common/JsonReader';

const MAX_DETAIL: number = 220;

function firstSentence(text: string): string {
  const cut: number = text.indexOf('. ');
  const first: string = cut > 0 ? text.substring(0, cut) : text;
  return first.length > MAX_DETAIL
    ? first.substring(0, MAX_DETAIL) + '…'
    : first;
}

/**
 * Extracts the AADSTS code and the useful part of `error_description`.
 * Falls back to `error` or the caller's message for non-OAuth payloads.
 */
export function oauthErrorMessage(body: string, fallback: string): string {
  const parsed: Object | null = parseJson(body);
  if (parsed === null) {
    return fallback;
  }
  const json: Record<string, Object> = parsed as Record<string, Object>;
  const desc: string = getStr(json, 'error_description');
  const err: string = getStr(json, 'error');
  if (desc.length === 0 && err.length === 0) {
    return fallback;
  }
  const match: RegExpExecArray | null = /AADSTS\d+/.exec(desc);
  const code: string = match !== null ? match[0] : '';
  let message: string = '';
  if (code.length > 0) {
    const after: string = desc.substring(desc.indexOf(code) + code.length)
      .replace(/^\s*[:-]\s*/, '');
    message = `${code}: ${firstSentence(after)}`;
  } else if (desc.length > 0) {
    message = firstSentence(desc);
  } else {
    message = firstSentence(err);
  }
  if (code === 'AADSTS700016') {
    message += ' The bundled Azure client id is not registered, or it does not ' +
      'accept personal Microsoft accounts (docs/BUILD.md §7).';
  } else if (code === 'AADSTS7000218') {
    message += ' Enable "Allow public client flows" on the app registration.';
  } else if (code === 'AADSTS65001' || code === 'AADSTS65004') {
    message += ' Grant consent for XboxLive.signin on the app registration.';
  }
  return message;
}

/** Known XSTS/XBL error codes; returns '' when the body has no Xbox error. */
export function xboxErrorMessage(body: string): string {
  const parsed: Object | null = parseJson(body);
  if (parsed === null) {
    return '';
  }
  const json: Record<string, Object> = parsed as Record<string, Object>;
  const code: number = getNum(json, 'XErr');
  if (code === 2148916233) {
    return 'This Microsoft account has no Xbox profile. Sign in at xbox.com ' +
      'to create one, then retry.';
  }
  if (code === 2148916235) {
    return 'Xbox Live is not available in this account\'s country or region.';
  }
  if (code === 2148916236 || code === 2148916237) {
    return 'This account needs adult verification at xbox.com before it can ' +
      'use Xbox Live.';
  }
  if (code === 2148916238) {
    return 'This is a child account. Add it to a Microsoft family and have an ' +
      'adult approve it, then retry.';
  }
  if (code > 0) {
    return `Xbox Live rejected the sign-in (error ${code}).`;
  }
  return '';
}
