/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import { VirtualControls } from '../ui/VirtualControls.ets';
import { ControlLayoutStore, ControlLayoutSpec } from '../ui/ControlLayout';
import { GameLauncherPushBridge } from './HomeTab.ets';

/**
 * Drag-and-drop editor for the virtual control overlay: reposition elements
 * by dragging, tune mouse sensitivity, save to preferences or reset.
 */

@Component
export struct ControlsEditorPage {
  @State layout: ControlLayoutSpec = { layoutVersion: 1, buttons: [], mouseSensitivity: 1.0 };
  @State dirty: boolean = false;
  @State savedHint: string = '';

  aboutToAppear(): void {
    ControlLayoutStore.load().then((layout: ControlLayoutSpec) => {
      this.layout = layout;
    });
  }

  private async save(): Promise<void> {
    await ControlLayoutStore.save(this.layout);
    this.dirty = false;
    this.savedHint = 'Layout saved.';
  }

  private async reset(): Promise<void> {
    this.layout = await ControlLayoutStore.reset();
    this.dirty = true;
    this.savedHint = 'Layout reset to default (not saved yet).';
  }

  build() {
    Stack() {
      VirtualControls({
        layout: this.layout,
        editMode: true
      })
        .width('100%')
        .height('100%')

      Column() {
        Row() {
          Button('✕')
            .width(36)
            .height(36)
            .fontSize(16)
            .backgroundColor('#2A3340')
            .onClick(() => {
              GameLauncherPushBridge.pop();
            })
          Blank()
          Button('Reset')
            .height(36)
            .fontSize(13)
            .backgroundColor('#B33A3A')
            .onClick(() => {
              this.reset();
            })
          Button('Save')
            .height(36)
            .fontSize(13)
            .backgroundColor(this.dirty ? '#63C36A' : '#3E5A43')
            .margin({ left: 8 })
            .onClick(() => {
              this.save();
            })
        }
        .width('100%')
        .padding(8)

        Row() {
          Text('Mouse sensitivity')
            .fontSize(12)
            .fontColor('#8FA0B3')
          Blank()
          Text(`${this.layout.mouseSensitivity.toFixed(1)}×`)
            .fontSize(12)
            .fontColor('#5FA8D3')
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 4 })
        Slider({ value: this.layout.mouseSensitivity * 10, min: 3, max: 30, step: 1 })
          .selectedColor('#5FA8D3')
          .width('100%')
          .padding({ left: 8, right: 8 })
          .onChange((value: number, mode: SliderChangeMode) => {
            this.layout = {
              layoutVersion: this.layout.layoutVersion,
              buttons: this.layout.buttons.slice(),
              mouseSensitivity: Math.round(value) / 10
            };
            this.dirty = true;
          })

        Text('Drag any element to reposition. Buttons dispatch the key while held.')
          .fontSize(11)
          .fontColor('#8FA0B3')
          .width('100%')
          .padding({ left: 8, right: 8, top: 4 })

        if (this.savedHint.length > 0) {
          Text(this.savedHint)
            .fontSize(11)
            .fontColor('#63C36A')
            .width('100%')
            .padding({ left: 8, top: 4 })
        }

        Blank()
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#14181F')
  }
}
