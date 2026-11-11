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
import cryptoFramework from '@ohos.security.cryptoFramework';
import emitter from '@ohos.events.emitter';

/**
 * A single download executed inside a taskpool worker. Each worker performs
 * the HTTP streaming download, SHA-1 verification and atomic rename, so the
 * UI thread only schedules tasks and consumes aggregate progress events.
 *
 * The spec/result types are plain data (serializable) as required by taskpool.
 */

export interface DownloadSpec {
  url: string;
  destPath: string;
  sha1?: string;
  sizeBytes?: number;
  label?: string;
}

export interface DownloadResult {
  spec: DownloadSpec;
  ok: boolean;
  httpCode: number;
  error?: string;
}

export interface DownloadProgressEvent {
  label: string;
  received: number;
  total: number;
  finished: boolean;
  failed: boolean;
}

export const DL_PROGRESS_EVENT_ID: number = 0x4D430002;

function emitProgress(event: DownloadProgressEvent): void {
  emitter.emit({
    eventId: DL_PROGRESS_EVENT_ID,
    priority: emitter.EventPriority.IMMEDIATE
  }, { data: {
    label: event.label,
    received: event.received,
    total: event.total,
    finished: event.finished,
    failed: event.failed
  } } as emitter.EventData);
}

function ensureParentDir(path: string): void {
  const idx: number = path.lastIndexOf('/');
  if (idx > 0) {
    const dir: string = path.substring(0, idx);
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir, true);
    }
  }
}

async function sha1HexOf(path: string): Promise<string> {
  const md: cryptoFramework.Md = cryptoFramework.createMd('SHA1');
  const stat: fs.Stat = fs.statSync(path);
  const buf: ArrayBuffer = new ArrayBuffer(1024 * 512);
  const fd: number = fs.openSync(path, fs.OpenMode.READ_ONLY).fd;
  try {
    for (let offset = 0; offset < stat.size; offset += buf.byteLength) {
      const toRead: number = Math.min(buf.byteLength, stat.size - offset);
      const len: number = fs.readSync(fd, buf, { offset: offset, length: toRead });
      await md.update({ data: new Uint8Array(buf.slice(0, len)) });
    }
  } finally {
    fs.closeSync(fd);
  }
  const digest: cryptoFramework.DataBlob = await md.digest();
  const bytes: Uint8Array = digest.data;
  let hex: string = '';
  for (let i = 0; i < bytes.length; i++) {
    hex += (bytes[i] < 16 ? '0' : '') + bytes[i].toString(16);
  }
  return hex;
}

/** Verify (or, when no checksum is known, pass through) a downloaded file. */
async function verifyChecksum(path: string, spec: DownloadSpec): Promise<string | null> {
  if (spec.sha1 === undefined || spec.sha1.length === 0) {
    return null;
  }
  const actual: string = await sha1HexOf(path);
  if (actual !== spec.sha1.toLowerCase()) {
    return `sha1 mismatch: expected ${spec.sha1}, got ${actual}`;
  }
  return null;
}

/**
 * taskpool worker entry point. Runs entirely off the UI thread.
 */
@Concurrent
export async function downloadOne(spec: DownloadSpec): Promise<DownloadResult> {
  const part: string = spec.destPath + '.part';
  let fd: number = -1;
  let received: number = 0;
  let total: number = 0;
  const client: http.HttpRequest = http.createHttp();
  try {
    ensureParentDir(spec.destPath);
    // Re-use an existing, verified file (idempotent resume).
    if (fs.accessSync(spec.destPath)) {
      const mismatch: string | null = await verifyChecksum(spec.destPath, spec);
      if (mismatch === null) {
        emitProgress({ label: specLabel(spec), received: 1, total: 1, finished: true, failed: false });
        return { spec: spec, ok: true, httpCode: 200 };
      }
      fs.unlinkSync(spec.destPath);
    }
    fs.unlinkSync(part);
    fd = fs.openSync(part, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC).fd;

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
        emitProgress({ label: specLabel(spec), received: received, total: total,
          finished: false, failed: false });
      }
    });
    const streamDone: Promise<void> = new Promise<void>((resolve: () => void) => {
      client.on('dataEnd', () => {
        resolve();
      });
    });

    const code: number = await client.requestInStream(spec.url, {
      method: http.RequestMethod.GET,
      header: { 'User-Agent': 'MC4HOS/1.0 (MPL-2.0)' },
      connectTimeout: 30000,
      readTimeout: 120000
    } as http.HttpRequestOptions);
    await streamDone;
    fs.closeSync(fd);
    fd = -1;
    client.destroy();

    if (!(code >= 200 && code < 300)) {
      fs.unlinkSync(part);
      emitProgress({ label: specLabel(spec), received: 0, total: total,
        finished: true, failed: true });
      return { spec: spec, ok: false, httpCode: code, error: `HTTP ${code}` };
    }

    const checksumError: string | null = await verifyChecksum(part, spec);
    if (checksumError !== null) {
      fs.unlinkSync(part);
      emitProgress({ label: specLabel(spec), received: 0, total: total,
        finished: true, failed: true });
      return { spec: spec, ok: false, httpCode: code, error: checksumError };
    }

    fs.renameSync(part, spec.destPath);
    emitProgress({ label: specLabel(spec), received: received, total: total,
      finished: true, failed: false });
    return { spec: spec, ok: true, httpCode: code };
  } catch (err) {
    const e = err as Error;
    try {
      if (fd >= 0) {
        fs.closeSync(fd);
      }
      if (fs.accessSync(part)) {
        fs.unlinkSync(part);
      }
    } catch (cleanupErr) {
      // best effort
    }
    client.destroy();
    emitProgress({ label: specLabel(spec), received: 0, total: total,
      finished: true, failed: true });
    return { spec: spec, ok: false, httpCode: -1, error: `${e.name}: ${e.message}` };
  }
}

function specLabel(spec: DownloadSpec): string {
  if (spec.label !== undefined && spec.label.length > 0) {
    return spec.label;
  }
  const idx: number = spec.url.lastIndexOf('/');
  return idx >= 0 ? spec.url.substring(idx + 1) : spec.url;
}
