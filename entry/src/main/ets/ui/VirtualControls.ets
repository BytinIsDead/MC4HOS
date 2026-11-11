/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import { sendKeyEvent, sendMouseButton, sendMouseMove, sendTouchEvent } from 'mc4hos_core.so';
import {
  ControlButtonSpec, ControlLayoutSpec, GlfwKeys, GlfwMouse
} from './ControlLayout';

/**
 * Custom on-screen input overlay: a mouse touchpad (drag = look, tap = click,
 * two-finger tap = right click), a directional pad, and configurable key
 * buttons. Every interaction is forwarded to the native input bridge, which
 * routes it into the game process through the Java-side InputBridge.
 *
 * Raw touch action codes follow the OHOS convention: 0 down, 1 up, 2 move,
 * 3 cancel.
 */

const ACTION_DOWN: number = 0;
const ACTION_UP: number = 1;
const ACTION_MOVE: number = 2;
const ACTION_CANCEL: number = 3;
const RAW_TOUCH_ID: number = -7; // virtual overlay pointer id space

/** Drag-edit position, in percent of the overlay canvas. */
interface DragPos {
  x: number;
  y: number;
}

@Component
export struct VirtualControls {
  @State layout: ControlLayoutSpec = { layoutVersion: 1, buttons: [], mouseSensitivity: 1.0 };
  @Prop editMode: boolean = false;
  /** Invoked after drag-editing moves an element (editor saves via store). */
  private onLayoutEdited: ((layout: ControlLayoutSpec) => void) | null = null;

  // touchpad state
  private lastX: number = -1;
  private lastY: number = -1;
  private downX: number = 0;
  private downY: number = 0;
  private downTimeMs: number = 0;
  private movedDistance: number = 0;
  private secondPointerSeen: boolean = false;

  public setOnLayoutEdited(callback: (layout: ControlLayoutSpec) => void): void {
    this.onLayoutEdited = callback;
  }

  public async loadLayout(layout: ControlLayoutSpec): Promise<void> {
    this.layout = layout;
  }

  // ---------------------------------------------------------------------
  // dispatch helpers
  // ---------------------------------------------------------------------

  private pressKeys(keys: Array<number>): void {
    for (const key of keys) {
      sendKeyEvent(key, 0);
    }
  }

  private releaseKeys(keys: Array<number>): void {
    for (const key of keys) {
      sendKeyEvent(key, 1);
    }
  }

  private forwardRawTouch(action: number, x: number, y: number): void {
    sendTouchEvent(RAW_TOUCH_ID, x, y, action);
  }

  private handleTouchpadTouch(event: TouchEvent): void {
    if (this.editMode) {
      return;
    }
    if (event.type === TouchType.Down) {
      this.lastX = event.touches[0].x;
      this.lastY = event.touches[0].y;
      this.downX = this.lastX;
      this.downY = this.lastY;
      this.downTimeMs = Date.now();
      this.movedDistance = 0;
      this.secondPointerSeen = event.touches.length > 1;
      this.forwardRawTouch(ACTION_DOWN, this.lastX, this.lastY);
      return;
    }
    if (event.type === TouchType.Move) {
      if (event.touches.length > 1) {
        this.secondPointerSeen = true;
      }
      if (this.lastX < 0) {
        return;
      }
      const nx: number = event.touches[0].x;
      const ny: number = event.touches[0].y;
      const dx: number = nx - this.lastX;
      const dy: number = ny - this.lastY;
      this.lastX = nx;
      this.lastY = ny;
      this.movedDistance += Math.abs(dx) + Math.abs(dy);
      sendMouseMove(dx * this.layout.mouseSensitivity, dy * this.layout.mouseSensitivity);
      this.forwardRawTouch(ACTION_MOVE, nx, ny);
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      const heldMs: number = Date.now() - this.downTimeMs;
      const isTap: boolean = this.movedDistance < 16 && heldMs < 250;
      this.forwardRawTouch(event.type === TouchType.Up ? ACTION_UP : ACTION_CANCEL,
        this.lastX < 0 ? 0 : this.lastX, this.lastY < 0 ? 0 : this.lastY);
      this.lastX = -1;
      this.lastY = -1;
      if (isTap && !this.secondPointerSeen) {
        // quick tap = left click (press + release)
        sendMouseButton(GlfwMouse.LEFT, 0);
        sendMouseButton(GlfwMouse.LEFT, 1);
      } else if (this.secondPointerSeen) {
        // two-finger tap/release = right click
        sendMouseButton(GlfwMouse.RIGHT, 0);
        sendMouseButton(GlfwMouse.RIGHT, 1);
      }
      this.secondPointerSeen = false;
    }
  }

  // ---------------------------------------------------------------------
  // builders
  // ---------------------------------------------------------------------

  @Builder
  private KeyButton(spec: ControlButtonSpec) {
    Column() {
      Text(spec.label)
        .fontSize(spec.sizeVp * 0.22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .maxLines(1)
    }
    .justifyContent(FlexAlign.Center)
    .width(spec.sizeVp)
    .height(spec.sizeVp)
    .borderRadius(spec.sizeVp / 2)
    .backgroundColor(spec.accentColor)
    .opacity(this.editMode ? 0.85 : 0.55)
    .position({ x: `${spec.xPercent}%`, y: `${spec.yPercent}%` })
    .markAnchor({ x: spec.sizeVp / 2, y: spec.sizeVp / 2 })
    .onTouch((event: TouchEvent) => {
      if (this.editMode) {
        return;
      }
      if (event.type === TouchType.Down) {
        this.pressKeys(spec.keyCodes);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.releaseKeys(spec.keyCodes);
      }
    })
    .gesture(this.editMode ? PanGesture({ fingers: 1, distance: 1 })
      .onActionStart(() => {
        this.dragStart.delete(spec.id);
      })
      .onActionUpdate((e: GestureEvent) => this.dragElement(spec, e))
      .onActionEnd(() => {
        this.dragStart.delete(spec.id);
        if (this.onLayoutEdited !== null) {
          this.onLayoutEdited(this.layout);
        }
      }) : undefined)
  }

  @Builder
  private MouseButton(spec: ControlButtonSpec) {
    Column() {
      Text(spec.label)
        .fontSize(spec.sizeVp * 0.24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
    }
    .justifyContent(FlexAlign.Center)
    .width(spec.sizeVp)
    .height(spec.sizeVp)
    .borderRadius(spec.sizeVp / 2)
    .backgroundColor(spec.accentColor)
    .opacity(this.editMode ? 0.85 : 0.6)
    .position({ x: `${spec.xPercent}%`, y: `${spec.yPercent}%` })
    .markAnchor({ x: spec.sizeVp / 2, y: spec.sizeVp / 2 })
    .onTouch((event: TouchEvent) => {
      if (this.editMode) {
        return;
      }
      if (event.type === TouchType.Down) {
        sendMouseButton(spec.mouseButton, 0);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        sendMouseButton(spec.mouseButton, 1);
      }
    })
    .gesture(this.editMode ? PanGesture({ fingers: 1, distance: 1 })
      .onActionStart(() => {
        this.dragStart.delete(spec.id);
      })
      .onActionUpdate((e: GestureEvent) => this.dragElement(spec, e))
      .onActionEnd(() => {
        this.dragStart.delete(spec.id);
        if (this.onLayoutEdited !== null) {
          this.onLayoutEdited(this.layout);
        }
      }) : undefined)
  }

  @Builder
  private DPad(spec: ControlButtonSpec) {
    Stack() {
      Column()
        .width(spec.sizeVp)
        .height(spec.sizeVp)
        .borderRadius(spec.sizeVp / 2)
        .backgroundColor('#00000000')
        .border({ width: 2, color: '#409FB6CD' })
      this.DPadNode(spec, '▲', 0, -1, GlfwKeys.W)
      this.DPadNode(spec, '◀', -1, 0, GlfwKeys.A)
      this.DPadNode(spec, '▼', 0, 1, GlfwKeys.S)
      this.DPadNode(spec, '▶', 1, 0, GlfwKeys.D)
    }
    .width(spec.sizeVp)
    .height(spec.sizeVp)
    .position({ x: `${spec.xPercent}%`, y: `${spec.yPercent}%` })
    .markAnchor({ x: spec.sizeVp / 2, y: spec.sizeVp / 2 })
    .gesture(this.editMode ? PanGesture({ fingers: 1, distance: 1 })
      .onActionStart(() => {
        this.dragStart.delete(spec.id);
      })
      .onActionUpdate((e: GestureEvent) => this.dragElement(spec, e))
      .onActionEnd(() => {
        this.dragStart.delete(spec.id);
        if (this.onLayoutEdited !== null) {
          this.onLayoutEdited(this.layout);
        }
      }) : undefined)
  }

  @Builder
  private DPadNode(spec: ControlButtonSpec, arrow: string, dx: number, dy: number, keyCode: number) {
    Text(arrow)
      .fontSize(spec.sizeVp * 0.18)
      .fontColor('#EAF2F8')
      .textAlign(TextAlign.Center)
      .width(spec.sizeVp * 0.36)
      .height(spec.sizeVp * 0.36)
      .borderRadius(spec.sizeVp * 0.18)
      .backgroundColor('#669FB6CD')
      .offset({ x: dx * spec.sizeVp * 0.28, y: dy * spec.sizeVp * 0.28 })
      .onTouch((event: TouchEvent) => {
        if (this.editMode) {
          return;
        }
        if (event.type === TouchType.Down) {
          sendKeyEvent(keyCode, 0);
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          sendKeyEvent(keyCode, 1);
        }
      })
  }

  private dragElement(spec: ControlButtonSpec, event: GestureEvent): void {
    // GestureEvent offsets are deltas; convert to percent using the canvas
    // size captured at drag start (approximated via component width).
    const dxPercent: number = event.offsetX / this.canvasWidth * 100;
    const dyPercent: number = event.offsetY / this.canvasHeight * 100;
    const base = this.dragBase(spec.id);
    spec.xPercent = clampPercent(base.x + dxPercent);
    spec.yPercent = clampPercent(base.y + dyPercent);
    this.layout = {
      layoutVersion: this.layout.layoutVersion,
      buttons: this.layout.buttons.slice(),
      mouseSensitivity: this.layout.mouseSensitivity
    };
    if (this.onLayoutEdited !== null) {
      this.onLayoutEdited(this.layout);
    }
  }

  /** Drag-edit position bookkeeping. Gesture classes cannot be used as
   * ArkTS return types, so the pan chains are written inline per builder. */
  private dragStart: Map<string, DragPos> = new Map();
  @State canvasWidth: number = 1;
  @State canvasHeight: number = 1;

  private dragBase(id: string): DragPos {
    const known = this.dragStart.get(id);
    if (known !== undefined) {
      return known;
    }
    const spec: ControlButtonSpec | undefined =
      this.layout.buttons.find((b: ControlButtonSpec) => b.id === id);
    const pos: DragPos = {
      x: spec !== undefined ? spec.xPercent : 50,
      y: spec !== undefined ? spec.yPercent : 50
    };
    this.dragStart.set(id, pos);
    return pos;
  }

  build() {
    Stack() {
      // Full-area mouse touchpad (also the drag-edit canvas).
      Column()
        .width('100%')
        .height('100%')
        .hitTestBehavior(this.editMode ? HitTestMode.Transparent : HitTestMode.Default)
        .onAreaChange((_old: Area, newArea: Area) => {
          this.canvasWidth = newArea.width as number;
          this.canvasHeight = newArea.height as number;
        })
        .onTouch((event: TouchEvent) => this.handleTouchpadTouch(event))

      ForEach(this.layout.buttons, (spec: ControlButtonSpec) => {
        if (spec.kind === 'dpad') {
          this.DPad(spec);
        } else if (spec.kind === 'mouse_button') {
          this.MouseButton(spec);
        } else {
          this.KeyButton(spec);
        }
      }, (spec: ControlButtonSpec) => spec.id)
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_old: Area, newArea: Area) => {
      this.canvasWidth = newArea.width as number;
      this.canvasHeight = newArea.height as number;
    })
  }
}

function clampPercent(value: number): number {
  return Math.min(98, Math.max(2, value));
}
