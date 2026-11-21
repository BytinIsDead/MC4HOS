/*
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#include "jvm_loader.h"
#include "jni_bridge.h"
#include "input_bridge.h"
#include "game_surface.h"
#include "log_capture.h"

#include <dlfcn.h>
#include <unistd.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <atomic>
#include <thread>

using CreateJvmFn = jint (*)(JavaVM **, JNIEnv **, void *);

namespace mc4hos::jvm {

namespace {

std::atomic<void *> g_javaVm{nullptr};
std::atomic<bool> g_running{false};
std::atomic<bool> g_exitRequested{false};

/**
 * Game thread: attaches to the VM, invokes `main(String[])` on the configured
 * main class and stays alive until it returns (or the VM exits).
 */
void GameThreadMain(LaunchConfig config) {
    JavaVM *vm = static_cast<JavaVM *>(g_javaVm.load());
    JNIEnv *env = nullptr;
    void *envPtr = nullptr;
    if (vm->AttachCurrentThread(&envPtr, nullptr) != JNI_OK) {
        log::Emit("[MC4HOS] AttachCurrentThread failed on game thread");
        g_running.store(false);
        return;
    }
    env = static_cast<JNIEnv *>(envPtr);

    // Announce bridge readiness, notify the Java-side platform handshake with
    // the live surface geometry, then flush queued overlay input.
    input::SetJvmReady(true);
    {
        jvalue sizeArgs[2];
        sizeArgs[0].i = static_cast<jint>(surface::SurfaceWidth());
        sizeArgs[1].i = static_cast<jint>(surface::SurfaceHeight());
        jni::CallStaticVoid(env, "org/mc4hos/bridge/PlatformBridge",
                            "onGameSurfaceCreated", "(II)V", sizeArgs);
    }
    input::DispatchPending(env);

    jclass mainClass = env->FindClass(config.mainClass.c_str());
    if (mainClass == nullptr) {
        jni::ReportException(env, "FindClass(main)");
        log::Emit("[MC4HOS] main class not found: " + config.mainClass);
        vm->DetachCurrentThread();
        g_running.store(false);
        return;
    }
    jmethodID mainMethod =
        env->GetStaticMethodID(mainClass, "main", "([Ljava/lang/String;)V");
    if (mainMethod == nullptr) {
        jni::ReportException(env, "GetStaticMethodID(main)");
        env->DeleteLocalRef(mainClass);
        vm->DetachCurrentThread();
        g_running.store(false);
        return;
    }

    jobjectArray gameArgs = env->NewObjectArray(
        static_cast<jsize>(config.gameArgs.size()), env->FindClass("java/lang/String"),
        nullptr);
    for (size_t i = 0; i < config.gameArgs.size(); i++) {
        env->SetObjectArrayElement(gameArgs, static_cast<jsize>(i),
                                   env->NewStringUTF(config.gameArgs[i].c_str()));
    }

    log::Emit("[MC4HOS] invoking " + config.mainClass + ".main(" +
              std::to_string(config.gameArgs.size()) + " args)");
    jvalue mainArg{};
    mainArg.l = gameArgs;
    env->CallStaticVoidMethodA(mainClass, mainMethod, &mainArg);
    if (env->ExceptionCheck()) {
        jni::ReportException(env, "main() threw");
    }
    log::Emit("[MC4HOS] game thread finished");

    env->DeleteLocalRef(gameArgs);
    env->DeleteLocalRef(mainClass);
    vm->DetachCurrentThread();
    g_running.store(false);
}

void PrependLdLibraryPath(const std::string &dirs) {
    if (dirs.empty()) {
        return;
    }
    const char *current = ::getenv("LD_LIBRARY_PATH");
    std::string value = dirs;
    if (current != nullptr && std::strlen(current) > 0) {
        value += ":";
        value += current;
    }
    ::setenv("LD_LIBRARY_PATH", value.c_str(), 1);
}

/**
 * Runtime images link libjvm against libcxxabi_shim.so (and libc++_shared,
 * which the HAP already loads). The loader does not search libjvm's own
 * directory for that dependency, so load it first by absolute path.
 */
void PreloadAbiShim(const std::string &home) {
    const std::vector<std::string> candidates = {
        home + "lib/libcxxabi_shim.so",
        home + "lib/aarch64/libcxxabi_shim.so",
        home + "lib/x86_64/libcxxabi_shim.so",
        home + "lib/arm64/libcxxabi_shim.so",
        home + "jre/lib/libcxxabi_shim.so",
        home + "jre/lib/aarch64/libcxxabi_shim.so",
        home + "jre/lib/x86_64/libcxxabi_shim.so",
    };
    for (const std::string &candidate : candidates) {
        if (::access(candidate.c_str(), R_OK) != 0) {
            continue;
        }
        if (::dlopen(candidate.c_str(), RTLD_NOW | RTLD_GLOBAL) != nullptr) {
            log::Emit("[MC4HOS] loaded " + candidate);
        } else {
            const char *err = ::dlerror();
            log::Emit(std::string("[MC4HOS] preload failed for ") + candidate + ": " +
                      (err != nullptr ? err : "unknown error"));
        }
        return;
    }
}

} // namespace

void SetGlobalJavaVM(void *vm) {
    g_javaVm.store(vm);
}

void *GetGlobalJavaVM() {
    return g_javaVm.load();
}

bool IsJvmRunning() {
    return g_running.load();
}

void RequestJvmExit() {
    if (!g_running.load()) {
        return;
    }
    if (g_exitRequested.exchange(true)) {
        return;
    }
    // Stop input dispatch before the VM begins shutting down; a JNI call
    // raced against System.exit can abort the process.
    input::SetJvmReady(false);
    JNIEnv *env = jni::AttachCurrentThread();
    if (env != nullptr) {
        jni::CallSystemExit(env, 0);
    }
}

int StartJvm(const LaunchConfig &config) {
    if (g_running.load()) {
        return kErrAlreadyRunning;
    }
    if (config.javaHome.empty()) {
        return kErrNoJavaHome;
    }

    std::string home = config.javaHome;
    if (home.back() != '/') {
        home += "/";
    }
    // JVM options below also read these, but the ABI shim must be resolvable
    // before libjvm itself is loaded.
    PrependLdLibraryPath(config.nativesDirs);
    PreloadAbiShim(home);
    // Modern OpenJDK images put the VM in lib/server/; JDK8 uses
    // lib/<arch>/server/. Try both, plus a nested jre/ in case the caller
    // passed the JDK root instead of the normalized JRE root.
    const std::vector<std::string> candidates = {
        home + "lib/server/libjvm.so",
        home + "lib/aarch64/server/libjvm.so",
        home + "lib/x86_64/server/libjvm.so",
        home + "lib/arm64/server/libjvm.so",
        home + "jre/lib/server/libjvm.so",
        home + "jre/lib/aarch64/server/libjvm.so",
        home + "jre/lib/x86_64/server/libjvm.so",
    };
    void *handle = nullptr;
    std::string libJvmPath;
    std::string lastError;
    for (const std::string &candidate : candidates) {
        handle = ::dlopen(candidate.c_str(), RTLD_NOW | RTLD_GLOBAL);
        if (handle != nullptr) {
            libJvmPath = candidate;
            break;
        }
        const char *err = ::dlerror();
        if (err != nullptr) {
            lastError = err;
        }
    }
    if (handle == nullptr) {
        log::Emit(std::string("[MC4HOS] dlopen(libjvm) failed: ") + lastError);
        log::Emit("[MC4HOS] javaHome=" + config.javaHome +
                  " — is an OpenHarmony OpenJDK runtime for this ABI installed? (docs/NATIVES.md)");
        return kErrLibJvmMissing;
    }
    log::Emit("[MC4HOS] loaded " + libJvmPath);
    auto createJvm = reinterpret_cast<CreateJvmFn>(::dlsym(handle, "JNI_CreateJavaVM"));
    if (createJvm == nullptr) {
        log::Emit(std::string("[MC4HOS] dlsym(JNI_CreateJavaVM) failed: ") + ::dlerror());
        return kErrLibJvmMissing;
    }

    // Runtime environment (best effort; the JVM reads these at init).
    ::setenv("JAVA_HOME", config.javaHome.c_str(), 1);

    // Assemble VM options: base properties first, then user options. The
    // classpath/library path have a single owner (this function): modern
    // version JSON also emits "-cp <classpath>" and "-Djava.library.path=…",
    // so those are dropped together with their values.
    std::vector<std::string> optionStrings;
    optionStrings.push_back("-Djava.home=" + config.javaHome);
    optionStrings.push_back("-Djava.class.path=" + config.classPath);
    optionStrings.push_back("-Djava.library.path=" + config.nativesDirs);
    optionStrings.push_back("-Duser.dir=" + config.workingDir);
    optionStrings.push_back("-Dsun.java.command=" + config.mainClass);
    for (size_t i = 0; i < config.jvmOptions.size(); i++) {
        const std::string &opt = config.jvmOptions[i];
        if (opt == "-cp" || opt == "-classpath") {
            // Skip the classpath value that follows the flag.
            i++;
            continue;
        }
        if (opt.rfind("-Djava.class.path=", 0) == 0 ||
            opt.rfind("-Djava.library.path=", 0) == 0 ||
            opt.rfind("-Djava.home=", 0) == 0 ||
            opt.rfind("-Duser.dir=", 0) == 0 ||
            opt.rfind("-Dsun.java.command=", 0) == 0) {
            continue;
        }
        optionStrings.push_back(opt);
    }

    std::vector<JavaVMOption> options;
    options.reserve(optionStrings.size());
    for (const std::string &opt : optionStrings) {
        JavaVMOption jvmOpt{};
        jvmOpt.optionString = const_cast<char *>(opt.c_str());
        options.push_back(jvmOpt);
    }

    JavaVMInitArgs vmArgs{};
    vmArgs.version = JNI_VERSION_1_8;
    vmArgs.nOptions = static_cast<jint>(options.size());
    vmArgs.options = options.data();
    // Version descriptors target the newest JDK; tolerate options the
    // installed runtime does not know instead of failing VM creation.
    vmArgs.ignoreUnrecognized = JNI_TRUE;

    log::Emit("[MC4HOS] creating JVM (" + std::to_string(options.size()) + " options)");
    JavaVM *vm = nullptr;
    JNIEnv *env = nullptr;
    jint result = createJvm(&vm, &env, &vmArgs);
    if (result != JNI_OK || vm == nullptr) {
        log::Emit("[MC4HOS] JNI_CreateJavaVM failed with code " + std::to_string(result));
        return kErrCreateFailed;
    }
    SetGlobalJavaVM(vm);
    g_exitRequested.store(false);
    g_running.store(true);
    // Note: GetVersion() is a JNIEnv function, not a JavaVM one.
    char jniVersion[16];
    std::snprintf(jniVersion, sizeof(jniVersion), "0x%x", env->GetVersion());
    log::Emit(std::string("[MC4HOS] JVM created (JNI version ") + jniVersion + ")");

    // Game loop on a dedicated thread; UI thread returns immediately.
    std::thread game(GameThreadMain, config);
    game.detach();
    return 0;
}

} // namespace mc4hos::jvm
