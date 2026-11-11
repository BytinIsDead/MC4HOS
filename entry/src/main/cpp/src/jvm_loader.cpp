/*
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
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

    std::string libJvmPath =
        config.javaHome + (config.javaHome.back() == '/' ? "" : "/") + "lib/server/libjvm.so";
    void *handle = ::dlopen(libJvmPath.c_str(), RTLD_NOW | RTLD_GLOBAL);
    if (handle == nullptr) {
        log::Emit(std::string("[MC4HOS] dlopen(libjvm) failed: ") + ::dlerror());
        log::Emit("[MC4HOS] javaHome=" + config.javaHome +
                  " — is an OpenHarmony aarch64 OpenJDK runtime installed? (docs/NATIVES.md)");
        return kErrLibJvmMissing;
    }
    auto createJvm = reinterpret_cast<CreateJvmFn>(::dlsym(handle, "JNI_CreateJavaVM"));
    if (createJvm == nullptr) {
        log::Emit(std::string("[MC4HOS] dlsym(JNI_CreateJavaVM) failed: ") + ::dlerror());
        return kErrLibJvmMissing;
    }

    // Runtime environment (best effort; the JVM reads these at init).
    ::setenv("JAVA_HOME", config.javaHome.c_str(), 1);
    PrependLdLibraryPath(config.nativesDirs);

    // Assemble VM options: base properties first, then user options. Note
    // classpath/library-path are supplied here, never as -cp flags.
    std::vector<std::string> optionStrings;
    optionStrings.push_back("-Djava.home=" + config.javaHome);
    optionStrings.push_back("-Djava.class.path=" + config.classPath);
    optionStrings.push_back("-Djava.library.path=" + config.nativesDirs);
    optionStrings.push_back("-Duser.dir=" + config.workingDir);
    optionStrings.push_back("-Dsun.java.command=" + config.mainClass);
    for (const std::string &opt : config.jvmOptions) {
        // The ArkTS builder must not emit -cp/-classpath; guard anyway.
        if (opt == "-cp" || opt == "-classpath" || opt.rfind("-Djava.class.path=", 0) == 0) {
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
    vmArgs.ignoreUnrecognized = JNI_FALSE;

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
