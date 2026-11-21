/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import {
  DownloadSpec, DownloadResult, DownloadProgressEvent,
  emitProgress, ensureParentDir, sha1HexOf, verifyChecksum, specLabel
} from './DownloadShared';

/**
 * A single download executed inside a taskpool worker. Each worker performs
 * the HTTP streaming download, SHA-1 verification and atomic rename; the UI
 * thread only schedules tasks and consumes aggregate progress events.
 *
 * The spec/result types and every helper live in DownloadShared.ets —
 * @Concurrent functions may only reference imported variables and locals,
 * so module-scope helpers in this file would not serialize into the worker.
 */

@Concurrent
export async function downloadOne(spec: DownloadSpec): Promise<DownloadResult> {
  const part: string = spec.destPath + '.part';
  let fd: number = -1;
  let received: number = 0;
  let total: number = 0;
  let lastReported: number = 0;
  const reportStep: number = 1024 * 1024;
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
    if (fs.accessSync(part)) {
      fs.unlinkSync(part);
    }
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
        // Throttle UI events: assets are often many small files and a
        // per-chunk emit floods the emitter queue.
        if (received - lastReported >= reportStep || (total > 0 && received >= total)) {
          lastReported = received;
          emitProgress({ label: specLabel(spec), received: received, total: total,
            finished: false, failed: false });
        }
      }
    });
    let watchdog: number = -1;
    const streamDone: Promise<void> = new Promise<void>((resolve: () => void,
      reject: (err: Error) => void) => {
      watchdog = setTimeout(() => {
        reject(new Error('download stream stalled'));
      }, 300000);
      client.on('dataEnd', () => {
        resolve();
      });
    });

    try {
      const code: number = await client.requestInStream(spec.url, {
        method: http.RequestMethod.GET,
        header: { 'User-Agent': 'MC4HOS/1.0 (MPL-2.0-no-copyleft-exception)' },
        connectTimeout: 30000,
        readTimeout: 120000
      } as http.HttpRequestOptions);
      await streamDone;
      fs.closeSync(fd);
      fd = -1;
      client.destroy();

      if (!(code >= 200 && code < 300)) {
        if (fs.accessSync(part)) {
          fs.unlinkSync(part);
        }
        emitProgress({ label: specLabel(spec), received: 0, total: total,
          finished: true, failed: true });
        return { spec: spec, ok: false, httpCode: code, error: `HTTP ${code}` };
      }

      const expectedSize: number = spec.sizeBytes ?? 0;
      if (expectedSize > 0 && received !== expectedSize) {
        if (fs.accessSync(part)) {
          fs.unlinkSync(part);
        }
        emitProgress({ label: specLabel(spec), received: received, total: total,
          finished: true, failed: true });
        return {
          spec: spec, ok: false, httpCode: code,
          error: `size mismatch: expected ${expectedSize}, got ${received}`
        };
      }

      const checksumError: string | null = await verifyChecksum(part, spec);
      if (checksumError !== null) {
        if (fs.accessSync(part)) {
          fs.unlinkSync(part);
        }
        emitProgress({ label: specLabel(spec), received: 0, total: total,
          finished: true, failed: true });
        return { spec: spec, ok: false, httpCode: code, error: checksumError };
      }

      fs.renameSync(part, spec.destPath);
      emitProgress({ label: specLabel(spec), received: received, total: total,
        finished: true, failed: false });
      return { spec: spec, ok: true, httpCode: code };
    } finally {
      if (watchdog >= 0) {
        clearTimeout(watchdog);
      }
    }
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
