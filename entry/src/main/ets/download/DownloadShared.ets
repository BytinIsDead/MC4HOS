/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import fs from '@ohos.file.fs';
import cryptoFramework from '@ohos.security.cryptoFramework';
import emitter from '@ohos.events.emitter';

/**
 * Shared types and helpers for the download pipeline.
 *
 * Lives in its own module because @Concurrent taskpool workers may only
 * reference *imported* variables — module-scope helpers in the worker's own
 * file are not serializable into the worker program.
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

export function emitProgress(event: DownloadProgressEvent): void {
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

export function ensureParentDir(path: string): void {
  const idx: number = path.lastIndexOf('/');
  if (idx > 0) {
    const dir: string = path.substring(0, idx);
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir, true);
    }
  }
}

export function specLabel(spec: DownloadSpec): string {
  if (spec.label !== undefined && spec.label.length > 0) {
    return spec.label;
  }
  const idx: number = spec.url.lastIndexOf('/');
  return idx >= 0 ? spec.url.substring(idx + 1) : spec.url;
}

export async function sha1HexOf(path: string): Promise<string> {
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
export async function verifyChecksum(path: string, spec: DownloadSpec): Promise<string | null> {
  if (spec.sha1 === undefined || spec.sha1.length === 0) {
    return null;
  }
  const actual: string = await sha1HexOf(path);
  if (actual !== spec.sha1.toLowerCase()) {
    return `sha1 mismatch: expected ${spec.sha1}, got ${actual}`;
  }
  return null;
}
