/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import window from '@ohos.window';
import { VirtualControls } from '../ui/VirtualControls.ets';
import { ControlLayoutStore, ControlLayoutSpec } from '../ui/ControlLayout';
import { GameLauncher, LaunchProgress } from '../launch/GameLauncher';
import { CONSOLE_EVENT_ID } from '../common/Logger';
import emitter from '@ohos.events.emitter';

/**
 * In-game view: hosts the native XComponent surface (rendered by the JVM's
 * OpenGL pipeline through libmc4hos_core.so) and layers the virtual mouse +
 * gamepad overlay on top. Forces landscape orientation and immersive mode.
 */

@Component
export struct GamePageView {
  @State surfaceReady: boolean = false;
  @State controlsVisible: boolean = true;
  @State overlayLayout: ControlLayoutSpec = { layoutVersion: 1, buttons: [], mouseSensitivity: 1.0 };
  @State progress: LaunchProgress = { phase: 'idle', message: '' };
  @State lastLogLines: Array<string> = [];
  @Consume('nav') navStack: NavPathStack;
  private consoleListener: ((event: emitter.EventData) => void) | null = null;

  aboutToAppear(): void {
    ControlLayoutStore.load().then((layout: ControlLayoutSpec) => {
      this.overlayLayout = layout;
    });
    GameLauncher.onProgress((p: LaunchProgress) => {
      this.progress = p;
    });
    this.consoleListener = (event: emitter.EventData) => {
      const data: Record<string, Object> | undefined = event.data;
      if (data === undefined) {
        return;
      }
      const message: string = data['message'] as string;
      if (message === undefined || message.length === 0) {
        return;
      }
      this.lastLogLines = this.lastLogLines.concat(message).slice(-4);
    };
    const consoleEvent: emitter.InnerEvent = { eventId: CONSOLE_EVENT_ID };
    emitter.on(consoleEvent, this.consoleListener);

    window.getLastWindow(getContext(this)).then((w: window.Window) => {
      w.setPreferredOrientation(window.Orientation.LANDSCAPE);
      w.setWindowLayoutFullScreen(true);
    });
  }

  aboutToDisappear(): void {
    if (this.consoleListener !== null) {
      const consoleEvent: emitter.InnerEvent = { eventId: CONSOLE_EVENT_ID };
      emitter.off(consoleEvent, this.consoleListener);
      this.consoleListener = null;
    }
    window.getLastWindow(getContext(this)).then((w: window.Window) => {
      w.setPreferredOrientation(window.Orientation.PORTRAIT);
      w.setWindowLayoutFullScreen(false);
    });
  }

  private async exitGame(): Promise<void> {
    AlertDialog.show({
      title: 'Leave game?',
      message: 'This terminates the embedded JVM. Unsaved worlds are lost.',
      primaryButton: {
        value: 'Cancel',
        action: () => {
        }
      },
      secondaryButton: {
        value: 'Exit',
        fontColor: '#D35F5F',
        action: () => {
          GameLauncher.stop().then(() => {
            this.navStack.pop();
          });
        }
      }
    });
  }

  build() {
    Stack() {
      // Native surface: 'library' names the NAPI module that receives the
      // OH_NativeXComponent pointer and EGL window on creation.
      XComponent({ id: 'game_surface', type: XComponentType.SURFACE, library: 'mc4hos_core' })
        .width('100%')
        .height('100%')
        .onLoad(() => {
          this.surfaceReady = true;
        })

      if (this.controlsVisible) {
        VirtualControls({ layout: this.overlayLayout, editMode: false })
      }

      // HUD: status + toggles
      Column() {
        Row() {
          Button('✕')
            .width(36)
            .height(36)
            .fontSize(16)
            .backgroundColor('#B33A3A')
            .onClick(() => {
              this.exitGame();
            })
          Button(this.controlsVisible ? 'Hide controls' : 'Show controls')
            .height(36)
            .fontSize(12)
            .backgroundColor('#2A3340')
            .margin({ left: 8 })
            .onClick(() => {
              this.controlsVisible = !this.controlsVisible;
            })
          Blank()
          Text(this.progress.phase === 'running' ? (this.surfaceReady ? 'Surface ready' : 'Starting…')
            : `${this.progress.phase} ${this.progress.message}`)
            .fontSize(11)
            .fontColor('#8FA0B3')
        }
        .width('100%')
        .padding(8)

        Blank()

        // Log ticker
        Column() {
          ForEach(this.lastLogLines, (line: string) => {
            Text(line)
              .fontSize(10)
              .fontColor('#9FB6CD')
              .maxLines(1)
              .width('100%')
          }, (line: string, idx: number) => `${idx}-${line.substring(0, 24)}`)
        }
        .width('100%')
        .padding(6)
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
