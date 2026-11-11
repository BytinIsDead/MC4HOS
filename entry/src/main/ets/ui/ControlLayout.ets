/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import { Logger } from '../common/Logger';

/**
 * Virtual control overlay model + persistence.
 *
 * Buttons dispatch keyboard/mouse events identified by GLFW key codes, which
 * is the scancode space the game's input layer (LWJGL) exposes. The numeric
 * values below are public constants of the GLFW API specification.
 */

const TAG: string = 'ControlLayout';
const PREF_NAME: string = 'mc4hos.controls';
const PREF_KEY: string = 'layoutJson';

/** GLFW key codes (subset used by the default overlay). */
export class GlfwKeys {
  public static readonly SPACE: number = 32;
  public static readonly APOSTROPHE: number = 39;
  public static readonly COMMA: number = 44;
  public static readonly MINUS: number = 45;
  public static readonly PERIOD: number = 46;
  public static readonly SLASH: number = 47;
  public static readonly KEY_0: number = 48;
  public static readonly KEY_1: number = 49;
  public static readonly KEY_2: number = 50;
  public static readonly KEY_3: number = 51;
  public static readonly KEY_4: number = 52;
  public static readonly KEY_5: number = 53;
  public static readonly KEY_6: number = 54;
  public static readonly KEY_7: number = 55;
  public static readonly KEY_8: number = 56;
  public static readonly KEY_9: number = 57;
  public static readonly SEMICOLON: number = 59;
  public static readonly A: number = 65;
  public static readonly B: number = 66;
  public static readonly C: number = 67;
  public static readonly D: number = 68;
  public static readonly E: number = 69;
  public static readonly F: number = 70;
  public static readonly G: number = 71;
  public static readonly H: number = 72;
  public static readonly I: number = 73;
  public static readonly J: number = 74;
  public static readonly K: number = 75;
  public static readonly L: number = 76;
  public static readonly M: number = 77;
  public static readonly N: number = 78;
  public static readonly O: number = 79;
  public static readonly P: number = 80;
  public static readonly Q: number = 81;
  public static readonly R: number = 82;
  public static readonly S: number = 83;
  public static readonly T: number = 84;
  public static readonly U: number = 85;
  public static readonly V: number = 86;
  public static readonly W: number = 87;
  public static readonly X: number = 88;
  public static readonly Y: number = 89;
  public static readonly Z: number = 90;
  public static readonly LEFT_SHIFT: number = 340;
  public static readonly LEFT_CONTROL: number = 341;
  public static readonly LEFT_ALT: number = 342;
  public static readonly ESCAPE: number = 256;
  public static readonly ENTER: number = 257;
  public static readonly TAB: number = 258;
  public static readonly F1: number = 290;
  public static readonly F3: number = 292;
  public static readonly F5: number = 294;
  public static readonly F11: number = 300;
}

/** GLFW mouse button ids. */
export class GlfwMouse {
  public static readonly LEFT: number = 0;
  public static readonly RIGHT: number = 1;
  public static readonly MIDDLE: number = 2;
}

export type ControlKind = 'button' | 'dpad' | 'dpad_node' | 'mousearea' | 'mouse_button';

export interface ControlButtonSpec {
  id: string;
  label: string;
  kind: ControlKind;
  /** Position of the button center, in percent of the overlay area. */
  xPercent: number;
  yPercent: number;
  /** Diameter in vp units. */
  sizeVp: number;
  /** GLFW key codes dispatched while the button is held. */
  keyCodes: Array<number>;
  /** GLFW mouse button id for kind 'mouse_button'. */
  mouseButton: number;
  accentColor: string;
}

export interface ControlLayoutSpec {
  layoutVersion: number;
  buttons: Array<ControlButtonSpec>;
  /** Mouse movement gain for the on-screen touchpad area. */
  mouseSensitivity: number;
}

function button(id: string, label: string, x: number, y: number, size: number,
  keys: Array<number>, color: string): ControlButtonSpec {
  return {
    id: id, label: label, kind: 'button', xPercent: x, yPercent: y, sizeVp: size,
    keyCodes: keys, mouseButton: -1, accentColor: color
  };
}

/** Default left-handed move cluster + essential game keys. */
export function defaultLayout(): ControlLayoutSpec {
  const buttons: Array<ControlButtonSpec> = [
    { id: 'dpad', label: '', kind: 'dpad', xPercent: 18, yPercent: 68, sizeVp: 170,
      keyCodes: [], mouseButton: -1, accentColor: '#9FB6CD' },
    button('jump', 'JUMP', 82, 74, 74, [GlfwKeys.SPACE], '#63C36A'),
    button('sneak', 'SNEAK', 70, 88, 64, [GlfwKeys.LEFT_SHIFT], '#8A7FBF'),
    button('inventory', 'INV', 60, 62, 58, [GlfwKeys.E], '#D9A94E'),
    button('chat', 'CHAT', 90, 60, 58, [GlfwKeys.T], '#5FA8D3'),
    button('esc', 'ESC', 94, 12, 58, [GlfwKeys.ESCAPE], '#D35F5F'),
    button('f3', 'F3', 84, 12, 58, [GlfwKeys.F3], '#5FA8D3'),
    button('persp', 'F5', 74, 12, 58, [GlfwKeys.F5], '#5FA8D3'),
    { id: 'mouse_left', label: 'LMB', kind: 'mouse_button', xPercent: 88, yPercent: 74,
      sizeVp: 70, keyCodes: [], mouseButton: GlfwMouse.LEFT, accentColor: '#63C36A' },
    { id: 'mouse_right', label: 'RMB', kind: 'mouse_button', xPercent: 95, yPercent: 86,
      sizeVp: 64, keyCodes: [], mouseButton: GlfwMouse.RIGHT, accentColor: '#D35F5F' }
  ];
  return { layoutVersion: 1, buttons: buttons, mouseSensitivity: 1.0 };
}

export class ControlLayoutStore {
  private static prefs: preferences.Preferences | null = null;

  public static async init(context: common.UIAbilityContext): Promise<void> {
    ControlLayoutStore.prefs =
      await preferences.getPreferences(context, { name: PREF_NAME });
  }

  public static async load(): Promise<ControlLayoutSpec> {
    if (ControlLayoutStore.prefs === null) {
      return defaultLayout();
    }
    const raw: string = await ControlLayoutStore.prefs.get(PREF_KEY, '') as string;
    if (raw.length === 0) {
      return defaultLayout();
    }
    try {
      return JSON.parse(raw) as ControlLayoutSpec;
    } catch (err) {
      Logger.warn(TAG, 'stored control layout corrupted; using default');
      return defaultLayout();
    }
  }

  public static async save(layout: ControlLayoutSpec): Promise<void> {
    if (ControlLayoutStore.prefs === null) {
      return;
    }
    await ControlLayoutStore.prefs.put(PREF_KEY, JSON.stringify(layout));
    await ControlLayoutStore.prefs.flush();
  }

  public static async reset(): Promise<ControlLayoutSpec> {
    const def: ControlLayoutSpec = defaultLayout();
    await ControlLayoutStore.save(def);
    return def;
  }
}
