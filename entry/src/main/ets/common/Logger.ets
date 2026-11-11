/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import hilog from '@ohos.hilog';
import emitter from '@ohos.events.emitter';

/**
 * Unified logger: writes to hilog and publishes every line to the in-app
 * console buffer so the Console tab and the in-game overlay can display it.
 */

export const LOG_LEVEL_DEBUG: number = 0;
export const LOG_LEVEL_INFO: number = 1;
export const LOG_LEVEL_WARN: number = 2;
export const LOG_LEVEL_ERROR: number = 3;

export interface LogLine {
  level: number;
  tag: string;
  message: string;
  timestampMs: number;
}

const LOG_DOMAIN: number = 0x4D43; // 'MC'
export const CONSOLE_EVENT_ID: number = 0x4D430001;

class ConsoleBufferImpl {
  private lines: LogLine[] = [];
  private readonly capacity: number = 4000;

  public push(line: LogLine): void {
    this.lines.push(line);
    if (this.lines.length > this.capacity) {
      this.lines.splice(0, this.lines.length - this.capacity);
    }
    emitter.emit({
      eventId: CONSOLE_EVENT_ID,
      priority: emitter.EventPriority.IMMEDIATE
    }, { data: { level: line.level, tag: line.tag, message: line.message } } as emitter.EventData);
  }

  public snapshot(): LogLine[] {
    return this.lines.slice();
  }

  public clear(): void {
    this.lines = [];
  }
}

export const ConsoleBuffer: ConsoleBufferImpl = new ConsoleBufferImpl();

function emit(level: number, tag: string, message: string): void {
  ConsoleBuffer.push({ level: level, tag: tag, message: message, timestampMs: Date.now() });
}

export class Logger {
  public static debug(tag: string, message: string): void {
    hilog.debug(LOG_DOMAIN, tag, '%{public}s', message);
    emit(LOG_LEVEL_DEBUG, tag, message);
  }

  public static info(tag: string, message: string): void {
    hilog.info(LOG_DOMAIN, tag, '%{public}s', message);
    emit(LOG_LEVEL_INFO, tag, message);
  }

  public static warn(tag: string, message: string): void {
    hilog.warn(LOG_DOMAIN, tag, '%{public}s', message);
    emit(LOG_LEVEL_WARN, tag, message);
  }

  public static error(tag: string, message: string): void {
    hilog.error(LOG_DOMAIN, tag, '%{public}s', message);
    emit(LOG_LEVEL_ERROR, tag, message);
  }

  /** Entry point for lines forwarded from the native layer (JVM stdout/stderr). */
  public static nativeLine(line: string): void {
    hilog.info(LOG_DOMAIN, 'Game', '%{public}s', line);
    let level: number = LOG_LEVEL_INFO;
    if (line.indexOf('ERROR') >= 0 || line.indexOf('Exception') >= 0) {
      level = LOG_LEVEL_ERROR;
    } else if (line.indexOf('WARN') >= 0) {
      level = LOG_LEVEL_WARN;
    }
    emit(level, 'Game', line);
  }
}
