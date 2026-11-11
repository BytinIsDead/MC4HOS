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

// startGame() return codes (mirror of jvm_loader.h):
//   0 OK | 1 already running | 2 missing javaHome/classPath/mainClass
//   3 dlopen(libjvm.so) failed | 4 JNI_CreateJavaVM failed.
// They are returned as the resolved number; no exported constants exist on
// the native module, so they are documented here instead of declared.

/** Installs the native log pump and routes JVM output to `logCallback`. */
export const initialize: (logCallback: (line: string) => void) => void;

/**
 * dlopen()s libjvm.so, creates the VM and invokes the main class on a
 * dedicated thread. Resolves with one of the return codes documented above.
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
