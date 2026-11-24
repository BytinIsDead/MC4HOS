/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import fs from '@ohos.file.fs';
import display from '@ohos.display';
import { Logger } from '../common/Logger';
import { Paths } from '../common/Paths';
import { DeployImport } from '../common/DeployImport';
import { KEY_DEMO_MODE } from '../common/AppState';
import { AccountStore } from '../auth/AccountStore';
import { VersionManifestInstance } from '../download/VersionManifest';
import { GameInstaller } from '../download/GameInstaller';
import { JavaRuntimeManager } from '../download/JavaRuntimeManager';
import { JvmArgumentBuilder } from './JvmArgumentBuilder';
import { BuiltLaunch, LaunchContext } from './LaunchConfig';
import {
  NativeLaunchConfig,
  initialize,
  startGame,
  stopGame,
  isGameRunning
} from 'libmc4hos_core.so';

/**
 * End-to-end launch pipeline:
 *
 *   1. resolve the selected version (manifest + per-version JSON)
 *   2. refresh the Minecraft services token if needed
 *   3. ensure client jar / libraries / assets are installed (idempotent)
 *   4. ensure an embedded JRE with the required major version exists
 *   5. build JVM + game arguments
 *   6. hand the plan to the native layer (libmc4hos_core.so) which loads
 *      libjvm.so and invokes the game's main class
 */

const TAG: string = 'GameLauncher';

export type LaunchPhase =
  | 'idle'
  | 'verifying_account'
  | 'installing'
  | 'preparing_runtime'
  | 'building_args'
  | 'starting'
  | 'running'
  | 'exited'
  | 'failed';

export interface LaunchProgress {
  phase: LaunchPhase;
  message: string;
}

export class GameLauncher {
  private static phaseListeners: Array<(p: LaunchProgress) => void> = [];
  private static currentPhase: LaunchPhase = 'idle';

  public static onProgress(listener: (p: LaunchProgress) => void): void {
    GameLauncher.phaseListeners.push(listener);
    listener({ phase: GameLauncher.currentPhase, message: '' });
  }

  /** Removes a previously registered listener (page lifecycle teardown). */
  public static offProgress(listener: (p: LaunchProgress) => void): void {
    GameLauncher.phaseListeners =
      GameLauncher.phaseListeners.filter((l: (p: LaunchProgress) => void) => l !== listener);
  }

  private static setPhase(phase: LaunchPhase, message: string): void {
    GameLauncher.currentPhase = phase;
    Logger.info(TAG, `[${phase}] ${message}`);
    for (const listener of GameLauncher.phaseListeners) {
      listener({ phase: phase, message: message });
    }
  }

  /** Registers the native log pump. Call once from EntryAbility. */
  public static bindNative(): void {
    initialize((line: string) => {
      Logger.nativeLine(line);
    });
  }

  public static running(): boolean {
    return isGameRunning();
  }

  /**
   * Boots the embedded JVM with the bundled bridge jar and runs
   * org.mc4hos.bridge.SelfTest — validates runtime pack, libjvm load, JNI
   * and classpath with zero Mojang/account involvement. On success also
   * queues the EGL surface self-test (renders when the game view opens).
   */
  private static async launchJvmSelfTest(): Promise<boolean> {
    GameLauncher.setPhase('preparing_runtime', 'Locating an installed Java runtime');
    const runtime = await JavaRuntimeManager.ensureAnyBundled();
    if (runtime === null) {
      GameLauncher.setPhase('failed',
        `No Java ${JavaRuntimeManager.bundledMajor()} runtime available — the HAP ` +
        'was built without the bundled runtime pack');
      return false;
    }
    const bridgeJar: string = `${Paths.base()}/bridge/mc4hos-bridge.jar`;
    if (!fs.accessSync(bridgeJar)) {
      GameLauncher.setPhase('failed',
        'mc4hos-bridge.jar missing from the HAP — rebuild with scripts/build_bridge_jar.py');
      return false;
    }
    const nativeLibDirs: Array<string> =
      JavaRuntimeManager.nativeLibraryDirs(runtime.homePath);
    const config: NativeLaunchConfig = {
      javaHome: runtime.homePath,
      classPath: bridgeJar,
      nativesDirs: nativeLibDirs.join(':'),
      // Mirror the descriptors the game launch path sets so the self-test
      // validates the same Java-visible environment.
      jvmOptions: [
        '-Xmx512M',
        '-Xms64M',
        `-Dmc4hos.natives.dir=${nativeLibDirs.join(':')}`,
        `-Dmc4hos.game.dir=${Paths.gameDir()}`,
        `-Dmc4hos.assets.dir=${Paths.assetsDir()}`
      ],
      mainClass: 'org.mc4hos.bridge.SelfTest',
      gameArgs: [],
      workingDir: Paths.gameDir(),
      logDir: Paths.logsDir(),
      selfTest: false
    };
    const started: number = await startGame(config);
    if (started !== 0) {
      GameLauncher.setPhase('failed', `JVM self-test failed (code ${started})`);
      return false;
    }
    // Queue the EGL surface self-test; it starts when the XComponent
    // surface is created (game view opened).
    const surfaceConfig: NativeLaunchConfig = {
      javaHome: '',
      classPath: '',
      nativesDirs: '',
      jvmOptions: [],
      mainClass: '',
      gameArgs: [],
      workingDir: Paths.gameDir(),
      logDir: Paths.logsDir(),
      selfTest: true
    };
    await startGame(surfaceConfig);
    GameLauncher.setPhase('running', 'Self-test active — JVM booted, surface pending');
    return true;
  }

  /** Full launch pipeline. Resolves true when the JVM started. */
  public static async launch(versionId: string): Promise<boolean> {
    if (GameLauncher.running()) {
      GameLauncher.setPhase('failed', 'A game instance is already running');
      return false;
    }
    // The HAP bundles the Java bridge; put it on disk before any JVM start.
    DeployImport.ensureBundledBridge();
    // Self-test mode: boot the embedded JVM with the bundled bridge jar and
    // run org.mc4hos.bridge.SelfTest — no Mojang services, no account, no
    // downloads. Then queue the EGL surface self-test for the game view.
    if (AppStorage.get<boolean>(KEY_DEMO_MODE) ?? false) {
      return await GameLauncher.launchJvmSelfTest();
    }
    try {
      // 1. version descriptor
      await VersionManifestInstance.load();
      const version = await VersionManifestInstance.fetchVersion(versionId);
      if (version === null) {
        GameLauncher.setPhase('failed', `Version ${versionId} could not be resolved`);
        return false;
      }

      // 2. account
      GameLauncher.setPhase('verifying_account', 'Checking account token');
      const token: string | null = await AccountStore.ensureValidMcToken();
      const profile = await AccountStore.loadActiveProfile();
      let playerName: string = 'Player';
      let playerUuid: string = '';
      let xuid: string = '';
      let mcToken: string = '0';
      if (token === null || profile === null) {
        GameLauncher.setPhase('failed', 'Not signed in. Add a Microsoft account first.');
        return false;
      }
      playerName = profile.displayName;
      playerUuid = profile.uuid;
      xuid = profile.xuid;
      mcToken = token;

      // 3. files
      GameLauncher.setPhase('installing', `Ensuring ${versionId} is installed`);
      const installed: boolean = await GameInstaller.ensureInstalled(version);
      if (!installed) {
        GameLauncher.setPhase('failed', 'Download failed — check network and retry');
        return false;
      }
      GameLauncher.setPhase('installing', 'Ensuring assets are installed');
      const assetIndexId: string = await GameInstaller.ensureAssets(version);
      if (assetIndexId.length === 0) {
        GameLauncher.setPhase('failed', 'Asset download failed');
        return false;
      }
      GameInstaller.markInstalled(version);

      // 4. runtime
      GameLauncher.setPhase('preparing_runtime',
        `Ensuring Java ${version.javaMajorVersion} runtime`);
      const runtime = await JavaRuntimeManager.ensureRuntime(version.javaMajorVersion);
      if (runtime === null) {
        const required: number = version.javaMajorVersion;
        const bundled: number = JavaRuntimeManager.bundledMajor();
        GameLauncher.setPhase('failed', required > bundled
          ? `This build runs games on Java ${bundled}; Java ${required} is not supported yet`
          : `No Java ${required} runtime installed — see docs/NATIVES.md`);
        return false;
      }

      // 5. arguments
      GameLauncher.setPhase('building_args', 'Building JVM arguments');
      const ramMb: number = AppStorage.get<number>('ramMb') ?? 2048;
      const scale: number = AppStorage.get<number>('resolutionScale') ?? 100;
      let baseWidth: number = 1280;
      let baseHeight: number = 720;
      try {
        const screen = display.getDefaultDisplaySync();
        if (screen.width > 0 && screen.height > 0) {
          baseWidth = screen.width;
          baseHeight = screen.height;
        }
      } catch (err) {
        const e = err as Error;
        Logger.warn(TAG, `display size unavailable, using 1280x720: ${e.message}`);
      }
      const ctx: LaunchContext = {
        version: version,
        gameDir: Paths.gameDir(),
        playerName: playerName,
        playerUuid: playerUuid,
        mcAccessToken: mcToken,
        xuid: xuid,
        ramMb: ramMb,
        resolutionWidth: Math.floor(baseWidth * scale / 100),
        resolutionHeight: Math.floor(baseHeight * scale / 100),
        nativesDir: Paths.nativesVersionDir(version.id),
        javaHome: runtime.homePath,
        extraJvmArgs: [],
        selfTest: false
      };
      const builder: JvmArgumentBuilder = new JvmArgumentBuilder(ctx);
      const built: BuiltLaunch | null = builder.build();
      if (built === null) {
        GameLauncher.setPhase('failed', 'Failed to build launch arguments');
        return false;
      }

      // 6. native launch
      GameLauncher.setPhase('starting', 'Starting JVM');
      const config: NativeLaunchConfig = {
        javaHome: built.javaHome,
        classPath: built.classPath,
        nativesDirs: built.nativesDirs,
        jvmOptions: built.jvmOptions,
        mainClass: built.mainClass,
        gameArgs: built.gameArgs,
        workingDir: built.workingDir,
        logDir: built.logDir,
        selfTest: built.selfTest
      };
      const started: number = await startGame(config);
      if (started !== 0) {
        GameLauncher.setPhase('failed', `Native launch failed (code ${started})`);
        return false;
      }
      GameLauncher.setPhase('running', 'Game running');
      return true;
    } catch (err) {
      const e = err as Error;
      GameLauncher.setPhase('failed', `Launch error: ${e.message}`);
      return false;
    }
  }

  /** Requests JVM termination through the native layer. */
  public static async stop(): Promise<void> {
    GameLauncher.setPhase('exited', 'Stopping game');
    await stopGame();
    GameLauncher.currentPhase = 'idle';
  }
}
