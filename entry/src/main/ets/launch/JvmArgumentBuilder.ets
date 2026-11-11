/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
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
import { BuiltLaunch, LaunchContext, LAUNCHER_NAME, LAUNCHER_VERSION } from './LaunchConfig';

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

  public constructor(ctx: LaunchContext) {
    this.ctx = ctx;
    this.fillPlaceholders();
  }

  /** Evaluates rules + placeholders and returns the full launch plan. */
  public build(): BuiltLaunch | null {
    const version = this.ctx.version;
    if (version.mainClass.length === 0) {
      Logger.error(TAG, `version ${version.id} has no mainClass`);
      return null;
    }

    const classPath: string = this.buildClassPath();
    if (classPath.length === 0) {
      Logger.error(TAG, 'classpath is empty; install the version first');
      return null;
    }

    const jvmOptions: Array<string> = this.buildJvmOptions();
    const gameArgs: Array<string> = this.buildGameArgs();

    Logger.info(TAG, `built launch for ${version.id}: ${jvmOptions.length} jvm opts, ` +
      `${gameArgs.length} game args`);
    return {
      javaHome: this.ctx.javaHome,
      classPath: classPath,
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
      if (rule.osArch !== 'arm64' && rule.osArch !== 'x86_64') {
        return false;
      }
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
    const bridgeJar: string = `${Paths.baseDir()}/bridge/mc4hos-bridge.jar`;
    if (fs.accessSync(bridgeJar)) {
      jars.push(bridgeJar);
    }

    for (const lib of this.ctx.version.libraries) {
      if (!GameInstaller.rulesAllow(lib.rules)) {
        continue;
      }
      if (lib.download === null || lib.download.url.length === 0) {
        continue;
      }
      const parts: Array<string> = lib.download.coord.split(':');
      if (parts.length !== 3) {
        continue;
      }
      jars.push(Paths.libraryPath(parts[0], parts[1], parts[2]));
    }

    const clientJar: string = Paths.clientJarPath(this.ctx.version.id);
    if (fs.accessSync(clientJar)) {
      jars.push(clientJar);
    } else {
      Logger.warn(TAG, `client jar missing: ${clientJar}`);
    }
    return jars.join(':');
  }

  private buildNativesDirs(): string {
    const dirs: Array<string> = [this.ctx.nativesDir];
    if (Paths.hapNativeLibraryDir().length > 0) {
      dirs.push(Paths.hapNativeLibraryDir());
    }
    dirs.push(`${this.ctx.javaHome}/lib/server`);
    dirs.push(`${this.ctx.javaHome}/lib`);
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
    // Inject custom resolution when both dimensions are configured.
    if (this.ctx.resolutionWidth > 0 && this.ctx.resolutionHeight > 0) {
      args.push('--width');
      args.push(`${this.ctx.resolutionWidth}`);
      args.push('--height');
      args.push(`${this.ctx.resolutionHeight}`);
    }
    return args;
  }
}
