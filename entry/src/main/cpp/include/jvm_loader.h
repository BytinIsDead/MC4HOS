/*
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef MC4HOS_JVM_LOADER_H
#define MC4HOS_JVM_LOADER_H

#include <string>
#include <vector>

namespace mc4hos::jvm {

/** Fully materialized launch plan handed over from ArkTS via NAPI. */
struct LaunchConfig {
    std::string javaHome;      // embedded JRE root (contains lib/, bin/)
    std::string classPath;     // ':' separated classpath
    std::string nativesDirs;   // ':' separated java.library.path
    std::vector<std::string> jvmOptions;
    std::string mainClass;     // e.g. net.minecraft.client.main.Main
    std::vector<std::string> gameArgs;
    std::string workingDir;    // game_directory
    std::string logDir;
    bool selfTest = false;     // run EGL/GLES surface self-test instead
};

/** StartJvm() error codes (mirrored in index.d.ts / GameLauncher). */
constexpr int kOk = 0;
constexpr int kErrAlreadyRunning = 1;
constexpr int kErrNoJavaHome = 2;
constexpr int kErrLibJvmMissing = 3;
constexpr int kErrCreateFailed = 4;

/**
 * dlopen()s `<javaHome>/lib/server/libjvm.so`, calls JNI_CreateJavaVM and
 * spawns the game thread. Returns 0 on success, non-zero error codes
 * otherwise (documented in napi_init.cpp).
 */
int StartJvm(const LaunchConfig &config);

bool IsJvmRunning();
void RequestJvmExit(); // graceful-ish: java.lang.System.exit(0) inside the VM

/** Global VM handle shared with jni_bridge / input_bridge. */
void SetGlobalJavaVM(void *vm);
void *GetGlobalJavaVM();

} // namespace mc4hos::jvm

#endif // MC4HOS_JVM_LOADER_H
