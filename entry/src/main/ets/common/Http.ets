/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import { Logger } from './Logger';

/**
 * Thin HTTP layer over @ohos.net.http used by the auth and download modules.
 * Download-to-file uses `requestInStream` so large game files never buffer in
 * memory.
 */

export interface HttpResult {
  code: number;
  body: string;
  ok: boolean;
}

const TAG: string = 'Http';
const DEFAULT_TIMEOUT_MS: number = 30000;

function mergeHeaders(a?: Record<string, string>,
  b?: Record<string, string>): Record<string, string> {
  const merged: Record<string, string> = {};
  if (a !== undefined) {
    const keys: Array<string> = Object.keys(a);
    for (const k of keys) {
      merged[k] = a[k];
    }
  }
  if (b !== undefined) {
    const keys: Array<string> = Object.keys(b);
    for (const k of keys) {
      merged[k] = b[k];
    }
  }
  return merged;
}

export async function getJson(url: string,
  headers?: Record<string, string>): Promise<HttpResult> {
  return request('GET', url, mergeHeaders(headers), '');
}

export async function postJson(url: string, body: string,
  headers?: Record<string, string>): Promise<HttpResult> {
  const base: Record<string, string> = { 'Content-Type': 'application/json' };
  return request('POST', url, mergeHeaders(base, headers), body);
}

export async function postForm(url: string, body: string,
  headers?: Record<string, string>): Promise<HttpResult> {
  const base: Record<string, string> =
    { 'Content-Type': 'application/x-www-form-urlencoded' };
  return request('POST', url, mergeHeaders(base, headers), body);
}

async function request(method: string, url: string, headers: Record<string, string>, body: string): Promise<HttpResult> {
  const client: http.HttpRequest = http.createHttp();
  try {
    const resp: http.HttpResponse = await client.request(url, {
      method: method === 'GET' ? http.RequestMethod.GET : http.RequestMethod.POST,
      header: headers,
      extraData: body.length > 0 ? body : undefined,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: DEFAULT_TIMEOUT_MS,
      readTimeout: DEFAULT_TIMEOUT_MS
    } as http.HttpRequestOptions);
    const code: number = resp.responseCode;
    const text: string = typeof resp.result === 'string' ? resp.result : '';
    client.destroy();
    return { code: code, body: text, ok: code >= 200 && code < 300 };
  } catch (err) {
    Logger.warn(TAG, `request ${method} ${url} failed: ${errToString(err)}`);
    client.destroy();
    return { code: -1, body: '', ok: false };
  }
}

export interface FileDownloadOptions {
  destPath: string;
  headers?: Record<string, string>;
  onProgress?: (received: number, total: number) => void;
}

/**
 * Streams `url` to `options.destPath` (written as `<destPath>.part`, then
 * atomically renamed once complete). Returns the HTTP status code, or -1 on
 * transport failure. The caller is responsible for checksum verification.
 */
export async function downloadToFile(url: string, options: FileDownloadOptions): Promise<number> {
  const dest: string = options.destPath;
  const partPath: string = dest + '.part';
  const client: http.HttpRequest = http.createHttp();
  let fd: number = -1;
  let received: number = 0;
  let total: number = 0;
  let lastReported: number = 0;
  const requestHeaders: Record<string, string> = mergeHeaders(options.headers);
  try {
    ensureParentDir(partPath);
    fs.unlinkSync(partPath);
    fd = fs.openSync(partPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC).fd;

    client.on('headersReceive', (h: Object) => {
      const headers = h as Record<string, Object>;
      const len: Object | undefined = headers['content-length'];
      if (typeof len === 'string') {
        total = parseInt(len as string, 10);
      } else if (typeof len === 'number') {
        total = len as number;
      }
    });
    client.on('dataReceive', (chunk: ArrayBuffer) => {
      if (fd >= 0 && chunk.byteLength > 0) {
        fs.writeSync(fd, chunk, { offset: received });
        received += chunk.byteLength;
        if (options.onProgress !== undefined && total > 0 && received - lastReported > 262144) {
          lastReported = received;
          options.onProgress(received, total);
        }
      }
    });
    const streamDone: Promise<void> = new Promise<void>((resolve: () => void) => {
      client.on('dataEnd', () => {
        resolve();
      });
    });

    const code: number = await client.requestInStream(url, {
      method: http.RequestMethod.GET,
      header: requestHeaders,
      connectTimeout: DEFAULT_TIMEOUT_MS,
      readTimeout: 120000
    } as http.HttpRequestOptions);

    await streamDone;
    fs.closeSync(fd);
    fd = -1;
    client.destroy();
    if (code >= 200 && code < 300) {
      fs.renameSync(partPath, dest);
      if (options.onProgress !== undefined) {
        options.onProgress(received, total > 0 ? total : received);
      }
      return code;
    }
    fs.unlinkSync(partPath);
    return code;
  } catch (err) {
    Logger.warn(TAG, `download ${url} failed: ${errToString(err)}`);
    try {
      if (fd >= 0) {
        fs.closeSync(fd);
      }
      fs.unlinkSync(partPath);
    } catch (cleanupErr) {
      // best effort cleanup
    }
    client.destroy();
    return -1;
  }
}

function ensureParentDir(path: string): void {
  const idx: number = path.lastIndexOf('/');
  if (idx <= 0) {
    return;
  }
  const dir: string = path.substring(0, idx);
  if (!fs.accessSync(dir)) {
    fs.mkdirSync(dir, true);
  }
}

export function errToString(err: Object | undefined): string {
  if (err === undefined || err === null) {
    return 'unknown error';
  }
  const e = err as Error;
  return `${e.name}: ${e.message}`;
}
