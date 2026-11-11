/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import emitter from '@ohos.events.emitter';
import { ConsoleBuffer, LogLine, LOG_LEVEL_WARN, LOG_LEVEL_ERROR, CONSOLE_EVENT_ID } from '../common/Logger';
import { Paths } from '../common/Paths';

/**
 * Launcher console: live log reader (hilog + native JVM output) with level
 * coloring, autoscroll, and export to the logs directory.
 */

@Component
export struct ConsolePage {
  @State lines: Array<LogLine> = [];
  @State autoscroll: boolean = true;
  private scroller: Scroller = new Scroller();
  private listener: ((event: emitter.EventData) => void) | null = null;

  aboutToAppear(): void {
    this.lines = ConsoleBuffer.snapshot();
    this.listener = (event: emitter.EventData) => {
      const data: Record<string, Object> | undefined = event.data;
      if (data === undefined) {
        return;
      }
      const message: string = data['message'] as string;
      if (message === undefined || message.length === 0) {
        return;
      }
      this.lines = ConsoleBuffer.snapshot();
      if (this.autoscroll) {
        this.scroller.scrollEdge(Edge.Bottom);
      }
    };
    const consoleEvent: emitter.InnerEvent = { eventId: CONSOLE_EVENT_ID };
    emitter.on(consoleEvent, this.listener);
  }

  aboutToDisappear(): void {
    if (this.listener !== null) {
      const consoleEvent: emitter.InnerEvent = { eventId: CONSOLE_EVENT_ID };
      emitter.off(consoleEvent, this.listener);
      this.listener = null;
    }
  }

  private colorFor(level: number): string {
    if (level === LOG_LEVEL_ERROR) {
      return '#D35F5F';
    }
    if (level === LOG_LEVEL_WARN) {
      return '#D9A94E';
    }
    return '#9FB6CD';
  }

  private saveLog(): void {
    const path: string = `${Paths.logsDir()}/console-${Date.now()}.log`;
    try {
      Paths.ensureDir(Paths.logsDir());
      Paths.writeTextFileSync(path, this.lines.map((l: LogLine) =>
        `[${new Date(l.timestampMs).toISOString()}] ${l.tag}: ${l.message}`).join('\n'));
      ConsoleBuffer.push({
        level: 1, tag: 'Console', message: `log saved to ${path}`, timestampMs: Date.now()
      });
      this.lines = ConsoleBuffer.snapshot();
    } catch (err) {
      // best effort
    }
  }

  build() {
    Column() {
      Row() {
        Text('Console')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
        Blank()
        Toggle({ type: ToggleType.Checkbox, isOn: this.autoscroll })
          .onChange((isOn: boolean) => {
            this.autoscroll = isOn;
          })
        Text('autoscroll')
          .fontSize(11)
          .fontColor('#8FA0B3')
          .margin({ right: 8 })
        Button('Save')
          .height(32)
          .fontSize(12)
          .backgroundColor('#2A3340')
          .onClick(() => {
            this.saveLog();
          })
        Button('Clear')
          .height(32)
          .fontSize(12)
          .backgroundColor('#2A3340')
          .margin({ left: 6 })
          .onClick(() => {
            ConsoleBuffer.clear();
            this.lines = [];
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Scroll(this.scroller) {
        Column() {
          ForEach(this.lines, (line: LogLine, index: number) => {
            Text(`${line.tag} › ${line.message}`)
              .fontSize(11)
              .fontColor(this.colorFor(line.level))
              .fontFamily('monospace')
              .width('100%')
              .padding({ left: 16, right: 16, top: 1, bottom: 1 })
          }, (line: LogLine, index: number) => `${index}-${line.timestampMs}`)
        }
        .constraintSize({ minWidth: '100%' })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_o: Area, _n: Area) => {
      this.lines = ConsoleBuffer.snapshot();
    })
  }
}
