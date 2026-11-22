/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  oauthErrorMessage,
  xboxErrorMessage
} from '../.build/core/auth/AuthErrors.ts';

const AAD_700016 = JSON.stringify({
  error: 'unauthorized_client',
  error_description:
    "AADSTS700016: Application with identifier '739dbf62-26b3-4b63-aa89-e5f5baef2a5b' " +
    "was not found in the directory '9188040d-6c67-4c5b-b112-36a304b66dad'. " +
    'This can happen if the application has not been installed by the administrator. ' +
    'Trace ID: abc Correlation ID: def Timestamp: 2026-11-22 12:25:03Z',
  error_codes: [700016]
});

test('oauthErrorMessage surfaces the AADSTS code and first sentence', () => {
  const message = oauthErrorMessage(AAD_700016, 'fallback');
  assert.match(message, /^AADSTS700016: Application with identifier/);
  assert.doesNotMatch(message, /Trace ID/);
  assert.match(message, /not registered/);
  assert.ok(message.length < 400);
});

test('oauthErrorMessage handles decline and consent codes', () => {
  const declined = JSON.stringify({
    error: 'authorization_declined',
    error_description: 'The user denied the request.'
  });
  assert.equal(oauthErrorMessage(declined, 'fallback'), 'The user denied the request.');

  const consent = JSON.stringify({
    error: 'invalid_grant',
    error_description: 'AADSTS65001: The user or administrator has not consented.'
  });
  assert.match(oauthErrorMessage(consent, 'fallback'), /AADSTS65001:/);
  assert.match(oauthErrorMessage(consent, 'fallback'), /Grant consent/);

  const publicClient = JSON.stringify({
    error: 'invalid_client',
    error_description: 'AADSTS7000218: The request body must contain client_assertion.'
  });
  assert.match(oauthErrorMessage(publicClient, 'fallback'), /Allow public client flows/);
});

test('oauthErrorMessage falls back for non-OAuth payloads', () => {
  assert.equal(oauthErrorMessage('', 'no body'), 'no body');
  assert.equal(oauthErrorMessage('<html>gateway</html>', 'gateway error'), 'gateway error');
  assert.equal(oauthErrorMessage('{"error":"server_error"}', 'fallback'), 'server_error');
});

test('xboxErrorMessage maps known XSTS errors', () => {
  assert.match(xboxErrorMessage('{"XErr":2148916233}'), /no Xbox profile/);
  assert.match(xboxErrorMessage('{"XErr":2148916235}'), /country or region/);
  assert.match(xboxErrorMessage('{"XErr":2148916236}'), /adult verification/);
  assert.match(xboxErrorMessage('{"XErr":2148916237}'), /adult verification/);
  assert.match(xboxErrorMessage('{"XErr":2148916238}'), /child account/);
  assert.match(xboxErrorMessage('{"XErr":2148917253}'), /error 2148917253/);
  assert.equal(xboxErrorMessage('{"XErr":0}'), '');
  assert.equal(xboxErrorMessage('not json'), '');
});
