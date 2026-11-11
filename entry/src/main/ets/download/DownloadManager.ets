/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import { taskpool } from '@kit.ArkTS';
import emitter from '@ohos.events.emitter';
import { Logger } from '../common/Logger';
import { DownloadSpec, DownloadResult, downloadOne, DL_PROGRESS_EVENT_ID } from './DownloadTask';

/**
 * Threaded download orchestrator. Schedules a fixed-size pool of taskpool
 * workers (default 6 concurrent streams — enough to saturate most links
 * without starving the UI thread) and reports aggregate progress.
 */

const TAG: string = 'DownloadManager';
export const DEFAULT_CONCURRENCY: number = 6;

export interface DownloadBatchOptions {
  concurrency?: number;
  onItemFinished?: (result: DownloadResult) => void;
}

export interface DownloadBatchResult {
  succeeded: Array<DownloadResult>;
  failed: Array<DownloadResult>;
}

export class DownloadManager {

  /** Subscribe once (e.g. from a page) to per-item progress events. */
  public static subscribeProgress(
    callback: (label: string, received: number, total: number, finished: boolean, failed: boolean) => void
  ): void {
    const progressEvent: emitter.InnerEvent = { eventId: DL_PROGRESS_EVENT_ID };
    emitter.on(progressEvent, (event: emitter.EventData) => {
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
    });
  }

  /**
   * Downloads every spec with bounded concurrency. Already-present verified
   * files are skipped inside the worker, making the whole batch idempotent.
   */
  public async downloadAll(specs: Array<DownloadSpec>,
    options: DownloadBatchOptions = {}): Promise<DownloadBatchResult> {
    const concurrency: number = options.concurrency ?? DEFAULT_CONCURRENCY;
    const succeeded: Array<DownloadResult> = [];
    const failed: Array<DownloadResult> = [];
    Logger.info(TAG, `downloading ${specs.length} files, concurrency ${concurrency}`);

    const queue: Array<DownloadSpec> = specs.slice();
    const workers: Array<Promise<void>> = [];
    for (let w = 0; w < Math.min(concurrency, queue.length); w++) {
      workers.push((async () => {
        while (queue.length > 0) {
          const spec: DownloadSpec | undefined = queue.shift();
          if (spec === undefined) {
            break;
          }
          try {
            const task: taskpool.Task = new taskpool.Task(downloadOne, spec);
            const result = await taskpool.execute(task) as DownloadResult;
            if (result.ok) {
              succeeded.push(result);
            } else {
              failed.push(result);
              Logger.warn(TAG, `failed ${spec.destPath}: ${result.error ?? 'unknown'}`);
            }
            if (options.onItemFinished !== undefined) {
              options.onItemFinished(result);
            }
          } catch (err) {
            const e = err as Error;
            const bad: DownloadResult = { spec: spec, ok: false, httpCode: -1, error: e.message };
            failed.push(bad);
            if (options.onItemFinished !== undefined) {
              options.onItemFinished(bad);
            }
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
