/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import fs from '@ohos.file.fs';
import { Logger } from '../common/Logger';
import { Paths } from '../common/Paths';
import { RuleSet, ArgEntry } from '../download/VersionManifest';
import { GameInstaller } from '../download/GameInstaller';
import { JavaRuntimeManager } from '../download/JavaRuntimeManager';
import {
  BuiltLaunch, LaunchContext, LAUNCHER_NAME, LAUNCHER_VERSION,
  LWJGL_JAR_NAME, LWJGL_GENERATION
} from './LaunchConfig';

/**
 * Constructs the complete JVM and game argument vectors from the version
 * descriptor.
 *
 * Supports both argument schemes of the vanilla launch protocol:
 *  - modern: rule-gated `arguments.jvm` / `arguments.game` template arrays
 *    with `${placeholder}` substitution (Minecraft ≥ 1.13);
 *  - legacy: `minecraftArguments` free-form string (Minecraft < 1.13), for
 *    which a classic default JVM option set is generated.
 *
 * This module evaluates the documented template placeholders and rule
 * semantics; it contains no game logic and no third-party code.
 */

const TAG: string = 'JvmArgs';

export class JvmArgumentBuilder {
  private readonly ctx: LaunchContext;
  private readonly placeholder: Map<string, string> = new Map();
  private readonly classPath: string;

  public constructor(ctx: LaunchContext) {
    this.ctx = ctx;
    // Computed up front because modern version descriptors reference
    // ${classpath} inside arguments.jvm.
    this.classPath = this.buildClassPath();
    this.fillPlaceholders();
  }

  /** Evaluates rules + placeholders and returns the full launch plan. */
  public build(): BuiltLaunch | null {
    const version = this.ctx.version;
    if (version.mainClass.length === 0) {
      Logger.error(TAG, `version ${version.id} has no mainClass`);
      return null;
    }

    if (this.classPath.length === 0) {
      Logger.error(TAG, 'classpath is empty; install the version first');
      return null;
    }

    const jvmOptions: Array<string> = this.buildJvmOptions();
    const gameArgs: Array<string> = this.buildGameArgs();

    Logger.info(TAG, `built launch for ${version.id}: ${jvmOptions.length} jvm opts, ` +
      `${gameArgs.length} game args`);
    return {
      javaHome: this.ctx.javaHome,
      classPath: this.classPath,
      nativesDirs: this.buildNativesDirs(),
      jvmOptions: jvmOptions,
      mainClass: version.mainClass,
      gameArgs: gameArgs,
      workingDir: this.ctx.gameDir,
      logDir: Paths.logsDir(),
      selfTest: this.ctx.selfTest
    };
  }

  // -----------------------------------------------------------------------
  // placeholder table
  // -----------------------------------------------------------------------

  private fillPlaceholders(): void {
    const p = this.placeholder;
    const v = this.ctx.version;
    p.set('auth_player_name', this.ctx.playerName);
    p.set('auth_uuid', this.ctx.playerUuid);
    p.set('auth_access_token', this.ctx.mcAccessToken);
    p.set('auth_xuid', this.ctx.xuid);
    p.set('clientid', this.ctx.playerUuid);
    p.set('user_type', 'msa');
    p.set('user_properties', '{}');
    p.set('version_name', v.id);
    p.set('version_type', v.type);
    p.set('assets_index_name', v.assetIndexId);
    p.set('assets_root', Paths.assetsDir());
    p.set('game_directory', this.ctx.gameDir);
    p.set('game_directory\\', this.ctx.gameDir);
    p.set('game_assets', Paths.assetsDir());
    p.set('launcher_name', LAUNCHER_NAME);
    p.set('launcher_version', LAUNCHER_VERSION);
    p.set('resolution_width', `${this.ctx.resolutionWidth}`);
    p.set('resolution_height', `${this.ctx.resolutionHeight}`);
    p.set('library_directory', Paths.librariesDir());
    p.set('classpath_separator', ':');
    p.set('classpath', this.classPath);
    p.set('natives_directory', this.ctx.nativesDir);
    p.set('primary_jar', Paths.clientJarPath(v.id));
    p.set('quickPlayPath', '');
    p.set('quickPlaySingleplayer', '');
    p.set('quickPlayMultiplayer', '');
    p.set('quickPlayRealms', '');
  }

  private substitute(template: string): string {
    let out: string = template;
    this.placeholder.forEach((value: string, key: string) => {
      const token: string = '${' + key + '}';
      if (out.indexOf(token) >= 0) {
        out = out.split(token).join(value);
      }
    });
    return out;
  }

  // -----------------------------------------------------------------------
  // rule evaluation
  // -----------------------------------------------------------------------

  private ruleAllows(rule: RuleSet): boolean | null {
    // Feature rules: only the features MC4HOS actually controls are matched;
    // unknown features evaluate to false.
    const featureKeys: Array<string> = rule.features !== undefined ? Object.keys(rule.features) : [];
    if (featureKeys.length > 0) {
      for (const key of featureKeys) {
        const wanted: boolean = rule.features !== undefined
          ? (rule.features[key] as boolean) : false;
        const actual: boolean | null = this.featureValue(key);
        if (actual === null || actual !== wanted) {
          return false;
        }
      }
    }
    if (rule.osName !== undefined && rule.osName.length > 0 && rule.osName !== 'linux') {
      return false;
    }
    if (rule.osArch !== undefined && rule.osArch.length > 0) {
      const abi: string = Paths.deviceAbi();
      const arch: string = abi === 'arm64-v8a' ? 'arm64' : abi;
      if (rule.osArch !== arch) {
        return false;
      }
    }
    if (rule.osVersion !== undefined && rule.osVersion.length > 0) {
      return false;
    }
    return true;
  }

  private featureValue(key: string): boolean | null {
    if (key === 'is_demo_user') {
      return false; // demo launch not supported with licensed accounts
    }
    if (key === 'has_custom_resolution') {
      return this.ctx.resolutionWidth > 0 && this.ctx.resolutionHeight > 0;
    }
    if (key === 'has_quick_plays_support' || key === 'is_quick_play_singleplayer' ||
      key === 'is_quick_play_multiplayer' || key === 'is_quick_play_realms') {
      return false;
    }
    return null;
  }

  private entryAllowed(entry: ArgEntry): boolean {
    if (entry.rules === undefined || entry.rules.length === 0) {
      return true;
    }
    // Vanilla semantics: default disallow; a matching 'allow' enables it,
    // a matching 'disallow' disables it again (last matching rule wins).
    let allowed: boolean = false;
    for (const rule of entry.rules) {
      if (this.ruleAllows(rule) === true) {
        allowed = rule.action === 'allow';
      }
    }
    return allowed;
  }

  // -----------------------------------------------------------------------
  // classpath
  // -----------------------------------------------------------------------

  private buildClassPath(): string {
    const jars: Array<string> = [];

    // Our clean-room Java-side bridge classes (input dispatch etc.), when
    // installed by the natives pipeline.
    const bridgeJar: string = `${Paths.base()}/bridge/mc4hos-bridge.jar`;
    if (!fs.accessSync(bridgeJar)) {
      Logger.error(TAG, `bridge jar missing: ${bridgeJar}`);
      return '';
    }
    jars.push(bridgeJar);

    const lwjglJar: string = `${Paths.base()}/bridge/${LWJGL_JAR_NAME}`;
    if (!fs.accessSync(lwjglJar)) {
      Logger.error(TAG, `adapted LWJGL jar missing: ${lwjglJar}`);
      return '';
    }
    jars.push(lwjglJar);

    for (const lib of this.ctx.version.libraries) {
      const coord: string = lib.download === null ? lib.name : lib.download.coord;
      if (coord.startsWith('org.lwjgl:') || coord.startsWith('org.lwjgl.lwjgl:')) {
        continue;
      }
      if (!GameInstaller.rulesAllow(lib.rules) || lib.natives !== null) {
        continue;
      }
      if (lib.download === null || lib.download.url.length === 0) {
        Logger.error(TAG, `required library has no artifact: ${lib.name}`);
        return '';
      }
      const parts: Array<string> = lib.download.coord.split(':');
      if (parts.length !== 3) {
        Logger.error(TAG, `invalid library coordinate: ${lib.name}`);
        return '';
      }
      const path: string = Paths.libraryPath(parts[0], parts[1], parts[2]);
      if (!fs.accessSync(path)) {
        Logger.error(TAG, `required library missing: ${path}`);
        return '';
      }
      jars.push(path);
    }

    const clientJar: string = Paths.clientJarPath(this.ctx.version.id);
    if (!fs.accessSync(clientJar)) {
      Logger.error(TAG, `client jar missing: ${clientJar}`);
      return '';
    }
    jars.push(clientJar);
    return jars.join(':');
  }

  private buildNativesDirs(): string {
    // The HAP's lib dir must come first: HarmonyOS only dlopens libraries
    // packaged there, including the JRE's own natives.
    const dirs: Array<string> = [];
    if (Paths.hapNativeLibraryDir().length > 0) {
      dirs.push(Paths.hapNativeLibraryDir());
    }
    dirs.push(this.ctx.nativesDir);
    // Runtime layout differs between JDK8 (lib/<arch>/) and modern JDKs
    // (lib/server/); the manager only returns directories that exist.
    for (const dir of JavaRuntimeManager.nativeLibraryDirs(this.ctx.javaHome)) {
      if (dirs.indexOf(dir) < 0) {
        dirs.push(dir);
      }
    }
    return dirs.join(':');
  }

  // -----------------------------------------------------------------------
  // jvm options
  // -----------------------------------------------------------------------

  private buildJvmOptions(): Array<string> {
    const opts: Array<string> = [];

    if (this.ctx.version.jvmArgs.length > 0) {
      // Modern scheme.
      opts.push(`-Xmx${this.ctx.ramMb}M`);
      opts.push(`-Xms${Math.min(this.ctx.ramMb, 512)}M`);
      opts.push('-XX:+UnlockExperimentalVMOptions');
      opts.push('-XX:+UseG1GC');
      opts.push('-XX:G1NewSizePercent=20');
      opts.push('-XX:G1ReservePercent=20');
      opts.push('-XX:MaxGCPauseMillis=50');
      opts.push('-XX:G1HeapRegionSize=32M');
      for (const entry of this.ctx.version.jvmArgs) {
        if (!this.entryAllowed(entry)) {
          continue;
        }
        if (entry.raw !== undefined) {
          opts.push(this.substitute(entry.raw));
        }
        if (entry.values !== undefined) {
          for (const value of entry.values) {
            opts.push(this.substitute(value));
          }
        }
      }
    } else {
      // Legacy scheme (pre-1.13): classic option set. java.library.path and
      // the classpath are applied by the native JVM loader, not here.
      opts.push(`-Xmx${this.ctx.ramMb}M`);
      opts.push(`-Xms${Math.min(this.ctx.ramMb, 512)}M`);
      opts.push('-Dorg.lwjgl.opengl.Display.allowSoftwareOpenGL=false');
      opts.push('-Djava.io.tmpdir=' + Paths.gameDir());
    }

    opts.push('-Dorg.lwjgl.opengl.libname=libGLv4.so');
    opts.push(`-Dorg.lwjgl.system.bundledLibrary.nameMapper=org.lwjgl.system.MeowBundledNameMapper`);
    opts.push(`-Dmeow.lwjgl.gen=${LWJGL_GENERATION}`);

    // MC4HOS environment descriptors consumed by the Java-side bridge layer.
    opts.push(`-Dmc4hos.natives.dir=${this.ctx.nativesDir}`);
    opts.push(`-Dmc4hos.game.dir=${this.ctx.gameDir}`);
    opts.push(`-Dmc4hos.assets.dir=${Paths.assetsDir()}`);

    for (const extra of this.ctx.extraJvmArgs) {
      if (extra.length > 0) {
        opts.push(extra);
      }
    }

    // Note: the classpath is NOT appended here. The native JVM loader sets
    // -Djava.class.path (and -Djava.library.path) from BuiltLaunch, keeping
    // a single owner for those arguments.
    return opts;
  }

  // -----------------------------------------------------------------------
  // game args
  // -----------------------------------------------------------------------

  private buildGameArgs(): Array<string> {
    const args: Array<string> = [];
    const v = this.ctx.version;
    if (v.gameArgs.length > 0) {
      for (const entry of v.gameArgs) {
        if (!this.entryAllowed(entry)) {
          continue;
        }
        if (entry.raw !== undefined) {
          args.push(this.substitute(entry.raw));
        }
        if (entry.values !== undefined) {
          for (const value of entry.values) {
            args.push(this.substitute(value));
          }
        }
      }
    } else if (v.legacyMinecraftArguments.length > 0) {
      for (const token of v.legacyMinecraftArguments.split(' ')) {
        if (token.length > 0) {
          args.push(this.substitute(token));
        }
      }
    }
    // Modern descriptors already emit --width/--height when the custom
    // resolution feature is enabled; only legacy arguments need them added.
    if (this.ctx.resolutionWidth > 0 && this.ctx.resolutionHeight > 0 &&
      args.indexOf('--width') < 0) {
      args.push('--width');
      args.push(`${this.ctx.resolutionWidth}`);
      args.push('--height');
      args.push(`${this.ctx.resolutionHeight}`);
    }
    return args;
  }
}
