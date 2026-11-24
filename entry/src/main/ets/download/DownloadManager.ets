/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import { taskpool } from '@kit.ArkTS';
import emitter from '@ohos.events.emitter';
import { Logger } from '../common/Logger';
import { DownloadSpec, DownloadResult, DL_PROGRESS_EVENT_ID } from './DownloadShared';
import { downloadOne } from './DownloadTask';

/**
 * Threaded download orchestrator. Schedules a fixed-size pool of taskpool
 * workers (default 6 concurrent streams — enough to saturate most links
 * without starving the UI thread) and reports aggregate progress.
 */

const TAG: string = 'DownloadManager';
export const DEFAULT_CONCURRENCY: number = 6;

export interface DownloadBatchOptions {
  concurrency?: number;
  /** taskpool priority for bulk asset downloads. */
  priority?: taskpool.Priority;
  /** Hard per-file timeout enforced by the API 24 taskpool config. */
  timeoutMs?: number;
  /** Total attempts per file (initial try included). */
  maxAttempts?: number;
  onItemFinished?: (result: DownloadResult) => void;
}

export interface DownloadBatchResult {
  succeeded: Array<DownloadResult>;
  failed: Array<DownloadResult>;
}

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}

function retryable(result: DownloadResult): boolean {
  if (result.ok) {
    return false;
  }
  if (result.httpCode === -1 || result.httpCode === 429 || result.httpCode >= 500) {
    return true;
  }
  // Size/checksum mismatches are usually truncated transfers worth retrying.
  const error: string = result.error ?? '';
  return error.indexOf('mismatch') >= 0 || error.indexOf('stalled') >= 0;
}

export class DownloadManager {

  /** Subscribes to per-item progress events; returns an unsubscribe function. */
  public static subscribeProgress(
    callback: (label: string, received: number, total: number, finished: boolean, failed: boolean) => void
  ): () => void {
    const progressEvent: emitter.InnerEvent = { eventId: DL_PROGRESS_EVENT_ID };
    const handler: (event: emitter.EventData) => void = (event: emitter.EventData) => {
      const data: Record<string, Object> | undefined = event.data;
      if (data === undefined) {
        return;
      }
      callback(
        data['label'] as string,
        data['received'] as number,
        data['total'] as number,
        data['finished'] as boolean,
        data['failed'] as boolean
      );
    };
    emitter.on(progressEvent, handler);
    return () => {
      emitter.off(DL_PROGRESS_EVENT_ID, handler);
    };
  }

  /**
   * Downloads every spec with bounded concurrency. Already-present verified
   * files are skipped inside the worker, making the whole batch idempotent.
   */
  public async downloadAll(specs: Array<DownloadSpec>,
    options: DownloadBatchOptions = {}): Promise<DownloadBatchResult> {
    const concurrency: number = options.concurrency ?? DEFAULT_CONCURRENCY;
    const maxAttempts: number = Math.max(1, options.maxAttempts ?? 3);
    const configs: taskpool.Configs = {
      priority: options.priority ?? taskpool.Priority.MEDIUM,
      timeout: options.timeoutMs ?? 600000
    };
    const succeeded: Array<DownloadResult> = [];
    const failed: Array<DownloadResult> = [];
    Logger.info(TAG, `downloading ${specs.length} files, concurrency ${concurrency}`);

    const queue: Array<DownloadSpec> = [];
    const destinations: Set<string> = new Set();
    for (const spec of specs) {
      if (!destinations.has(spec.destPath)) {
        destinations.add(spec.destPath);
        queue.push(spec);
      }
    }
    const workers: Array<Promise<void>> = [];
    for (let w = 0; w < Math.min(concurrency, queue.length); w++) {
      workers.push((async () => {
        while (queue.length > 0) {
          const spec: DownloadSpec | undefined = queue.shift();
          if (spec === undefined) {
            break;
          }
          let result: DownloadResult = { spec: spec, ok: false, httpCode: -1 };
          for (let attempt = 1; attempt <= maxAttempts; attempt++) {
            try {
              const task: taskpool.Task = new taskpool.Task(downloadOne, spec);
              result = await taskpool.execute(task, configs) as DownloadResult;
            } catch (err) {
              const e = err as Error;
              result = { spec: spec, ok: false, httpCode: -1, error: e.message };
            }
            if (result.ok || !retryable(result) || attempt === maxAttempts) {
              break;
            }
            Logger.warn(TAG,
              `${spec.destPath} attempt ${attempt}/${maxAttempts} failed ` +
              `(${result.error ?? result.httpCode}); retrying`);
            await delay(1000 * attempt);
          }
          if (result.ok) {
            succeeded.push(result);
          } else {
            failed.push(result);
            Logger.warn(TAG, `failed ${spec.destPath}: ${result.error ?? 'unknown'}`);
          }
          if (options.onItemFinished !== undefined) {
            options.onItemFinished(result);
          }
        }
      })());
    }
    await Promise.all(workers);
    Logger.info(TAG, `batch done: ${succeeded.length} ok, ${failed.length} failed`);
    return { succeeded: succeeded, failed: failed };
  }
}

export const DownloadManagerInstance: DownloadManager = new DownloadManager();
