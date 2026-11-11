/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import { VersionJson } from '../download/VersionManifest';

/**
 * Inputs and outputs of the launch pipeline, shared between the argument
 * builder, the launcher and the native bridge.
 */

/** Everything the JVM argument builder needs to construct a launch. */
export interface LaunchContext {
  version: VersionJson;
  /** Directory passed as the game working directory (worlds, options.txt). */
  gameDir: string;
  playerName: string;
  playerUuid: string;
  mcAccessToken: string;
  xuid: string;
  ramMb: number;
  resolutionWidth: number;
  resolutionHeight: number;
  /** Directory holding OpenHarmony-built natives (liblwjgl.so etc.). */
  nativesDir: string;
  /** Runtime home directory of the selected embedded JRE. */
  javaHome: string;
  /** Optional user-supplied JVM flags appended after the defaults. */
  extraJvmArgs: Array<string>;
  /** Run the native self-test renderer instead of starting the game. */
  selfTest: boolean;
}

/** Result of the argument builder, consumed by GameLauncher. */
export interface BuiltLaunch {
  javaHome: string;
  /** Full -classpath value (colon separated, POSIX). */
  classPath: string;
  /** Value for -Djava.library.path (colon separated). */
  nativesDirs: string;
  jvmOptions: Array<string>;
  mainClass: string;
  gameArgs: Array<string>;
  workingDir: string;
  logDir: string;
  selfTest: boolean;
}

export const LAUNCHER_NAME: string = 'MC4HOS';
export const LAUNCHER_VERSION: string = '1.0.0';
