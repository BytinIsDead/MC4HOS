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
#include <pthread.h>
#include <thread>

using CreateJvmFn = jint (*)(JavaVM **, JNIEnv **, void *);

namespace mc4hos::jvm {

namespace {

std::atomic<void *> g_javaVm{nullptr};
std::atomic<bool> g_running{false};
std::atomic<bool> g_exitRequested{false};

/**
 * The primordial thread cannot detach while the VM lives; park it so the
 * process (and VM) stay consistent until shutdown.
 */
void ParkPrimordialThread() {
    g_running.store(false);
    while (!g_exitRequested.load()) {
        ::sleep(1);
    }
}

/**
 * Game thread: runs `main(String[])` on the configured main class and stays
 * alive until it returns (or the VM exits). Must be called on the thread that
 * created the VM: JNI_CreateJavaVM makes its caller the VM's primordial Java
 * thread, so no attach is needed (and detaching it would be wrong).
 */
void GameThreadMain(LaunchConfig config, JNIEnv *env) {
    log::Emit("[MC4HOS] game thread running");

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
    surface::PublishNativeWindow();
    if (config.mainClass != "org.mc4hos.bridge.SelfTest") {
        jvalue monitorArgs[2];
        monitorArgs[0].i = static_cast<jint>(surface::SurfaceWidth());
        monitorArgs[1].i = static_cast<jint>(surface::SurfaceHeight());
        if (!jni::CallStaticVoid(env, "org/lwjgl/glfw/GLFW",
                                 "internalChangeMonitorSize", "(II)V", monitorArgs)) {
            log::Emit("[MC4HOS] LWJGL monitor initialization failed");
        }
    }
    log::Emit("[MC4HOS] bridge handshake done");
    input::DispatchPending(env);
    log::Emit("[MC4HOS] pending input flushed");

    // JNI names are slash-separated; the launch config uses dots.
    std::string mainClassName = config.mainClass;
    for (char &c : mainClassName) {
        if (c == '.') {
            c = '/';
        }
    }
    jclass mainClass = env->FindClass(mainClassName.c_str());
    if (mainClass == nullptr) {
        jni::ReportException(env, "FindClass(main)");
        log::Emit("[MC4HOS] main class not found: " + config.mainClass);
        ParkPrimordialThread();
        return;
    }
    jmethodID mainMethod =
        env->GetStaticMethodID(mainClass, "main", "([Ljava/lang/String;)V");
    if (mainMethod == nullptr) {
        jni::ReportException(env, "GetStaticMethodID(main)");
        env->DeleteLocalRef(mainClass);
        ParkPrimordialThread();
        return;
    }

    jobjectArray gameArgs = env->NewObjectArray(
        static_cast<jsize>(config.gameArgs.size()), env->FindClass("java/lang/String"),
        nullptr);
    log::Emit("[MC4HOS] main class + args prepared");
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
    ParkPrimordialThread();
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
 *
 * HarmonyOS only loads shared libraries from the HAP (`…/bundle/libs/<abi>`)
 * or system paths, so the packaged copy in `nativesDirs` comes first; the
 * sandbox copies extracted from a runtime pack are kept as a fallback for
 * layouts this platform may allow later.
 */
void PreloadAbiShim(const std::string &home, const std::vector<std::string> &nativeDirs) {
    std::vector<std::string> candidates;
    for (const std::string &dir : nativeDirs) {
        candidates.push_back(dir + "/libcxxabi_shim.so");
    }
    candidates.insert(candidates.end(), {
        home + "lib/libcxxabi_shim.so",
        home + "lib/aarch64/libcxxabi_shim.so",
        home + "lib/x86_64/libcxxabi_shim.so",
        home + "lib/arm64/libcxxabi_shim.so",
        home + "jre/lib/libcxxabi_shim.so",
        home + "jre/lib/aarch64/libcxxabi_shim.so",
        home + "jre/lib/x86_64/libcxxabi_shim.so",
    });
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

std::vector<std::string> SplitNativeDirs(const std::string &dirs) {
    std::vector<std::string> out;
    size_t start = 0;
    while (start <= dirs.size()) {
        size_t end = dirs.find(':', start);
        if (end == std::string::npos) {
            end = dirs.size();
        }
        if (end > start) {
            out.push_back(dirs.substr(start, end - start));
        }
        if (end == dirs.size()) {
            break;
        }
        start = end + 1;
    }
    return out;
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

/**
 * Embedding contract required by the OHOS OpenJDK build (patch
 * "ohos-embedded-boundary"): the VM honors JAVA_HOME and
 * SUN_BOOT_LIBRARY_PATH only when the host exports this symbol and it
 * returns 1. Our process embeds the VM, so the sandbox-incompatible
 * path inference must give way to the injected locations.
 */
extern "C" __attribute__((visibility("default"))) int amcl_jvm_is_embedded(void) {
    return 1;
}

/**
 * Hand-off between StartJvm() and the dedicated VM thread: the thread that
 * calls JNI_CreateJavaVM becomes the VM's primordial Java thread, so that
 * call must not happen on the ArkTS UI thread.
 */
struct VmBoot {
    CreateJvmFn createJvm = nullptr;
    JavaVMInitArgs *vmArgs = nullptr;
    std::string logDir;
    LaunchConfig config;
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    bool done = false;
    int status = kOk;
};

void PublishBootResult(VmBoot *boot, int status) {
    pthread_mutex_lock(&boot->mutex);
    boot->done = true;
    boot->status = status;
    pthread_cond_signal(&boot->cond);
    pthread_mutex_unlock(&boot->mutex);
}

void *VmThreadEntry(void *arg) {
    VmBoot *boot = static_cast<VmBoot *>(arg);
    // HotSpot may terminate the process from inside JNI_CreateJavaVM; anything
    // it prints to stdout/stderr would die with the pipe reader, so point the
    // standard descriptors at a boot log for the duration of the call.
    FILE *bootLog = nullptr;
    int savedStdout = -1;
    int savedStderr = -1;
    if (!boot->logDir.empty()) {
        bootLog = std::fopen((boot->logDir + "/jvm-boot.log").c_str(), "a");
        if (bootLog != nullptr) {
            savedStdout = ::dup(STDOUT_FILENO);
            savedStderr = ::dup(STDERR_FILENO);
            ::dup2(::fileno(bootLog), STDOUT_FILENO);
            ::dup2(::fileno(bootLog), STDERR_FILENO);
        }
    }

    JavaVM *vm = nullptr;
    JNIEnv *env = nullptr;
    jint result = boot->createJvm(&vm, &env, boot->vmArgs);

    if (bootLog != nullptr) {
        std::fflush(bootLog);
        ::dup2(savedStdout, STDOUT_FILENO);
        ::dup2(savedStderr, STDERR_FILENO);
        ::close(savedStdout);
        ::close(savedStderr);
        std::fclose(bootLog);
    }
    if (result != JNI_OK || vm == nullptr) {
        log::Emit("[MC4HOS] JNI_CreateJavaVM failed with code " + std::to_string(result));
        PublishBootResult(boot, kErrCreateFailed);
        return nullptr;
    }
    SetGlobalJavaVM(vm);
    g_exitRequested.store(false);
    g_running.store(true);
    char jniVersion[16];
    std::snprintf(jniVersion, sizeof(jniVersion), "0x%x", env->GetVersion());
    log::Emit(std::string("[MC4HOS] JVM created (JNI version ") + jniVersion + ")");
    PublishBootResult(boot, kOk);

    GameThreadMain(boot->config, env);
    return nullptr;
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
    const std::vector<std::string> nativeDirs = SplitNativeDirs(config.nativesDirs);
    PrependLdLibraryPath(config.nativesDirs);
    if (config.mainClass != "org.mc4hos.bridge.SelfTest") {
        ::setenv("MEOWCRAFT_RENDERER", "openglv4", 1);
        ::setenv("MEOWCRAFT_GL_PROFILE", "core", 1);
        ::setenv("ALSOFT_LOGLEVEL", "0", 1);
        ::setenv("vblank_mode", "0", 1);
        ::setenv("GALLIUM_THREAD", "0", 1);
        ::setenv("HOME", config.workingDir.c_str(), 1);
        const std::string cacheDir = config.workingDir + "/.cache";
        ::setenv("XDG_CACHE_HOME", cacheDir.c_str(), 1);
        ::setenv("MESA_SHADER_CACHE_DIR", (cacheDir + "/mesa").c_str(), 1);
        if (!nativeDirs.empty()) {
            ::setenv("MEOWCRAFT_NATIVEDIR", nativeDirs.front().c_str(), 1);
        }
        if (::chdir(config.workingDir.c_str()) != 0) {
            log::Emit("[MC4HOS] chdir(game directory) failed: " + config.workingDir);
        }
        void *renderer = ::dlopen("libGLv4.so", RTLD_NOW | RTLD_GLOBAL);
        if (renderer == nullptr) {
            const char *error = ::dlerror();
            log::Emit(std::string("[MC4HOS] desktop GL renderer unavailable: ") +
                      (error == nullptr ? "unknown error" : error));
            return kErrRendererMissing;
        }
        log::Emit("[MC4HOS] desktop GL renderer loaded");
        if (!surface::LoadNativeBridge(nativeDirs)) {
            return kErrNativeBridgeMissing;
        }
    }
    PreloadAbiShim(home, nativeDirs);
    // libjvm discovers the embedding contract through dlsym(RTLD_DEFAULT);
    // make sure this library sits in the global scope.
    {
        Dl_info info{};
        if (::dladdr(reinterpret_cast<void *>(&amcl_jvm_is_embedded), &info) != 0 &&
            info.dli_fname != nullptr) {
            ::dlopen(info.dli_fname, RTLD_NOW | RTLD_GLOBAL);
            log::Emit(std::string("[MC4HOS] host lib in global scope: ") + info.dli_fname);
        }
        log::Emit(std::string("[MC4HOS] amcl contract visible: ") +
                  (::dlsym(RTLD_DEFAULT, "amcl_jvm_is_embedded") != nullptr ? "yes" : "no"));
    }
    // HotSpot derives its bootstrap library directory (jimage, zip, java)
    // from the loaded libjvm's location, i.e. the sandbox runtime image,
    // where HarmonyOS refuses dlopen. The OHOS OpenJDK build honors
    // SUN_BOOT_LIBRARY_PATH instead; point it at the HAP copies.
    ::setenv("SUN_BOOT_LIBRARY_PATH", config.nativesDirs.c_str(), 1);
    // Modern OpenJDK images put the VM in lib/server/; JDK8 uses
    // lib/<arch>/server/. The JRE natives packaged in the HAP are the only
    // ones HarmonyOS can load here, so those directories come first, followed
    // by the runtime image's own layout for other platforms/layouts.
    std::vector<std::string> candidates;
    for (const std::string &dir : nativeDirs) {
        candidates.push_back(dir + "/libjvm.so");
    }
    candidates.insert(candidates.end(), {
        home + "lib/server/libjvm.so",
        home + "lib/aarch64/server/libjvm.so",
        home + "lib/x86_64/server/libjvm.so",
        home + "lib/arm64/server/libjvm.so",
        home + "jre/lib/server/libjvm.so",
        home + "jre/lib/aarch64/server/libjvm.so",
        home + "jre/lib/x86_64/server/libjvm.so",
        "libjvm.so",
    });
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

    // Runtime environment (best effort; the JVM reads these at init). The
    // OHOS OpenJDK build takes java.home from JAVA_HOME and its bootstrap
    // library directory from SUN_BOOT_LIBRARY_PATH (set above).
    ::setenv("JAVA_HOME", config.javaHome.c_str(), 1);
    {
        const std::string modules = config.javaHome + "/lib/modules";
        log::Emit("[MC4HOS] java.home=" + config.javaHome +
                  " lib/modules " + (::access(modules.c_str(), R_OK) == 0 ? "ok" : "missing"));
    }

    // Assemble VM options: base properties first, then user options. The
    // classpath/library path have a single owner (this function): modern
    // version JSON also emits "-cp <classpath>" and "-Djava.library.path=…",
    // so those are dropped together with their values.
    std::vector<std::string> optionStrings;
    optionStrings.push_back("-Djava.class.path=" + config.classPath);
    optionStrings.push_back("-Djava.library.path=" + config.nativesDirs);
    if (!config.logDir.empty()) {
        optionStrings.push_back("-XX:ErrorFile=" + config.logDir + "/hs_err_%p.log");
    }
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
            opt.rfind("-Dsun.boot.library.path=", 0) == 0 ||
            opt.rfind("-Djava.home=", 0) == 0 ||
            opt.rfind("-Dsun.java.launcher.is_altjvm=", 0) == 0 ||
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

    // The caller is the ArkTS UI thread; it must stay a plain native thread.
    // JNI_CreateJavaVM turns its caller into the VM's primordial Java thread,
    // which HotSpot assumes stays inside Java until shutdown — if the UI
    // thread went back to ArkTS, VM operations (class init, safepoints) would
    // fault on it. Create the VM on a dedicated thread instead; musl's default
    // 128 KB stack is far too small for HotSpot frames and JNI class loading,
    // so give it a full-size stack.
    VmBoot boot;
    boot.createJvm = createJvm;
    boot.vmArgs = &vmArgs;
    boot.logDir = config.logDir;
    boot.config = config;
    pthread_mutex_init(&boot.mutex, nullptr);
    pthread_cond_init(&boot.cond, nullptr);

    pthread_attr_t stackAttr;
    pthread_attr_init(&stackAttr);
    pthread_attr_setstacksize(&stackAttr, 16 * 1024 * 1024);
    pthread_t vmThread;
    if (::pthread_create(&vmThread, &stackAttr, VmThreadEntry, &boot) != 0) {
        pthread_attr_destroy(&stackAttr);
        pthread_mutex_destroy(&boot.mutex);
        pthread_cond_destroy(&boot.cond);
        log::Emit("[MC4HOS] failed to start the VM thread");
        return kErrCreateFailed;
    }
    ::pthread_detach(vmThread);
    pthread_attr_destroy(&stackAttr);

    // Wait for the create result so the caller gets the same error codes as
    // before; the VM thread keeps running main() afterwards.
    pthread_mutex_lock(&boot.mutex);
    while (!boot.done) {
        pthread_cond_wait(&boot.cond, &boot.mutex);
    }
    pthread_mutex_unlock(&boot.mutex);
    pthread_mutex_destroy(&boot.mutex);
    pthread_cond_destroy(&boot.cond);
    return boot.status;
}

} // namespace mc4hos::jvm
