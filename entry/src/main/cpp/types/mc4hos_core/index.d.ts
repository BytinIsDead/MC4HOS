/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/**
 * Type surface of libmc4hos_core.so consumed by the ArkTS layer.
 */

/** Launch plan produced by JvmArgumentBuilder and passed to startGame(). */
export interface NativeLaunchConfig {
  /** Embedded JRE root directory (contains lib/server/libjvm.so). */
  javaHome: string;
  /** ':' separated classpath. */
  classPath: string;
  /** ':' separated java.library.path entries. */
  nativesDirs: string;
  /** JVM options (memory, GC, system properties). No -cp entries. */
  jvmOptions: Array<string>;
  /** Game entry point, e.g. 'net.minecraft.client.main.Main'. */
  mainClass: string;
  /** Game (program) arguments after placeholder substitution. */
  gameArgs: Array<string>;
  /** Game working directory (game_directory). */
  workingDir: string;
  /** Directory for captured JVM stdout/stderr (latest.log). */
  logDir: string;
  /** Run the native EGL/GLES self-test instead of the JVM. */
  selfTest: boolean;
}

/** startGame() return codes (mirror of jvm_loader.h). */
export const START_OK: number = 0;
export const ERR_ALREADY_RUNNING: number = 1;
export const ERR_NO_JAVA_HOME: number = 2;
export const ERR_LIB_JVM_MISSING: number = 3;
export const ERR_CREATE_FAILED: number = 4;

/** Installs the native log pump and routes JVM output to `logCallback`. */
export const initialize: (logCallback: (line: string) => void) => void;

/**
 * dlopen()s libjvm.so, creates the VM and invokes the main class on a
 * dedicated thread. Resolves with a START_*/ERR_* code immediately.
 */
export const startGame: (config: NativeLaunchConfig) => Promise<number>;

/** Requests VM termination via java.lang.System.exit(0). */
export const stopGame: () => Promise<void>;

export const isGameRunning: () => boolean;

/** GLFW key-code space; action: 0 press, 1 release. */
export const sendKeyEvent: (code: number, action: number) => void;

/** GLFW mouse buttons; action: 0 press, 1 release. */
export const sendMouseButton: (button: number, action: number) => void;

/** Relative pointer motion (virtual mouse look). */
export const sendMouseMove: (dx: number, dy: number) => void;

/**
 * Raw absolute touch event on the game surface.
 * Action codes: 0 down, 1 up, 2 move, 3 cancel.
 */
export const sendTouchEvent: (id: number, x: number, y: number, action: number) => void;
