/*
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#include "game_surface.h"
#include "input_bridge.h"
#include "log_capture.h"
#include "jni_bridge.h"
#include "jvm_loader.h"

#include <ace/xcomponent/native_interface_xcomponent.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <unistd.h>
#include <cmath>
#include <atomic>
#include <mutex>
#include <thread>

namespace mc4hos::surface {

namespace {

std::mutex g_mutex;
void *g_window = nullptr;
std::atomic<uint32_t> g_width{0};
std::atomic<uint32_t> g_height{0};

std::atomic<bool> g_selfTestRunning{false};
std::atomic<bool> g_selfTestPending{false};
std::atomic<bool> g_surfaceAlive{false};

// -------------------------------------------------------------------------
// EGL self-test renderer (spinning triangle). The production game renders
// through the JVM-side LWJGL stack against the same native window.
// -------------------------------------------------------------------------

void RenderLoop() {
    EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (display == EGL_NO_DISPLAY) {
        log::Emit("[MC4HOS] self-test: eglGetDisplay failed");
        return;
    }
    if (!eglInitialize(display, nullptr, nullptr)) {
        log::Emit("[MC4HOS] self-test: eglInitialize failed");
        return;
    }
    const EGLint configAttribs[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
        EGL_NONE
    };
    EGLConfig config = nullptr;
    EGLint numConfigs = 0;
    eglChooseConfig(display, configAttribs, &config, 1, &numConfigs);
    if (config == nullptr || numConfigs == 0) {
        log::Emit("[MC4HOS] self-test: eglChooseConfig failed");
        return;
    }
    // On LP64 OHOS targets the generic EGLNativeWindowType (unsigned long)
    // and the OHNativeWindow pointer are both 64-bit; route the pointer
    // through uintptr_t so the cast is valid regardless of which branch of
    // eglplatform.h defined the typedef.
    EGLSurface eglSurface =
        eglCreateWindowSurface(display, config,
                               static_cast<EGLNativeWindowType>(
                                   reinterpret_cast<uintptr_t>(NativeWindow())),
                               nullptr);
    EGLContext context = EGL_NO_CONTEXT;
    const EGLint contextAttribs[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
    context = eglCreateContext(display, config, EGL_NO_CONTEXT, contextAttribs);
    if (eglSurface == EGL_NO_SURFACE || context == EGL_NO_CONTEXT ||
        !eglMakeCurrent(display, eglSurface, eglSurface, context)) {
        log::Emit("[MC4HOS] self-test: EGL surface/context setup failed");
        return;
    }

    log::Emit("[MC4HOS] self-test renderer online: " + std::to_string(g_width.load()) + "x" +
              std::to_string(g_height.load()));
    // Verification loop: animated clear color + swap. Proves the
    // XComponent -> EGLNativeWindow -> GLES surface pipeline end to end;
    // the game itself renders through the JVM-side LWJGL stack on the same
    // native window.
    float intensity = 0.0f;
    while (g_selfTestRunning.load() && g_surfaceAlive.load()) {
        glViewport(0, 0, static_cast<GLsizei>(g_width.load()),
                   static_cast<GLsizei>(g_height.load()));
        intensity = 0.5f + 0.5f * std::sin(intensity + 0.05f);
        glClearColor(0.10f + 0.1f * intensity, 0.24f + 0.3f * intensity, 0.16f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        eglSwapBuffers(display, eglSurface);
        usleep(16000);
    }
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(display, context);
    eglDestroySurface(display, eglSurface);
    eglTerminate(display);
    log::Emit("[MC4HOS] self-test renderer stopped");
}

void NotifyJavaSurface(uint32_t width, uint32_t height) {
    if (!jvm::IsJvmRunning()) {
        return;
    }
    JNIEnv *env = jni::AttachCurrentThread();
    if (env == nullptr) {
        return;
    }
    jvalue args[2];
    args[0].i = static_cast<jint>(width);
    args[1].i = static_cast<jint>(height);
    jni::CallStaticVoid(env, "org/mc4hos/bridge/PlatformBridge",
                        "onGameSurfaceChanged", "(II)V", args);
}

} // namespace

void OnSurfaceCreated(OH_NativeXComponent *component, void *window) {
    bool startSelfTest = false;
    uint32_t width = 0;
    uint32_t height = 0;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        g_window = window;
        g_surfaceAlive.store(true);
        if (component != nullptr && window != nullptr) {
            uint64_t sizeW = 0;
            uint64_t sizeH = 0;
            OH_NativeXComponent_GetXComponentSize(component, window, &sizeW, &sizeH);
            width = static_cast<uint32_t>(sizeW);
            height = static_cast<uint32_t>(sizeH);
            g_width.store(width);
            g_height.store(height);
        } else {
            width = g_width.load();
            height = g_height.load();
        }
        log::Emit("[MC4HOS] surface created " + std::to_string(width) + "x" +
                  std::to_string(height));
        // Start the renderer only after geometry is known so the first
        // frame uses the real viewport.
        startSelfTest = g_selfTestPending.exchange(false);
        if (startSelfTest) {
            g_selfTestRunning.store(true);
        }
    }
    if (startSelfTest) {
        std::thread(RenderLoop).detach();
    }
    NotifyJavaSurface(width, height);
}

void OnSurfaceChanged(OH_NativeXComponent *component, void *window) {
    uint32_t width = 0;
    uint32_t height = 0;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        if (component != nullptr && window != nullptr) {
            uint64_t sizeW = 0;
            uint64_t sizeH = 0;
            OH_NativeXComponent_GetXComponentSize(component, window, &sizeW, &sizeH);
            width = static_cast<uint32_t>(sizeW);
            height = static_cast<uint32_t>(sizeH);
            g_width.store(width);
            g_height.store(height);
        } else {
            width = g_width.load();
            height = g_height.load();
        }
        log::Emit("[MC4HOS] surface changed " + std::to_string(width) + "x" +
                  std::to_string(height));
    }
    NotifyJavaSurface(width, height);
}

void OnSurfaceDestroyed(OH_NativeXComponent *component, void *window) {
    (void)component;
    (void)window;
    std::lock_guard<std::mutex> lock(g_mutex);
    g_surfaceAlive.store(false);
    g_window = nullptr;
    log::Emit("[MC4HOS] surface destroyed");
}

void DispatchTouchEvent(OH_NativeXComponent *component, void *window) {
    OH_NativeXComponent_TouchEvent touch{};
    OH_NativeXComponent_GetTouchEvent(component, window, &touch);
    int action = input::ACTION_MOVE;
    switch (touch.type) {
        case OH_NATIVEXCOMPONENT_DOWN:
            action = input::ACTION_DOWN;
            break;
        case OH_NATIVEXCOMPONENT_UP:
            action = input::ACTION_UP;
            break;
        case OH_NATIVEXCOMPONENT_MOVE:
            action = input::ACTION_MOVE;
            break;
        case OH_NATIVEXCOMPONENT_CANCEL:
            action = input::ACTION_CANCEL;
            break;
        default:
            return;
    }
    // Raw touches on the game surface are forwarded as absolute pointer
    // events; the ArkTS overlay emits its own virtual-mouse stream on top.
    input::PostTouch(static_cast<int>(touch.id), touch.x, touch.y, action);
}

void *NativeWindow() {
    std::lock_guard<std::mutex> lock(g_mutex);
    return g_window;
}

uint32_t SurfaceWidth() {
    return g_width.load();
}

uint32_t SurfaceHeight() {
    return g_height.load();
}

void StartSelfTest() {
    if (!g_surfaceAlive.load() || NativeWindow() == nullptr) {
        // Queue: the renderer starts automatically once the surface exists.
        g_selfTestPending.store(true);
        log::Emit("[MC4HOS] self-test queued — starts when the surface is created");
        return;
    }
    if (g_selfTestRunning.exchange(true)) {
        return;
    }
    std::thread(RenderLoop).detach();
}

void StartSelfTestWhenSurfaceReady() {
    if (g_selfTestRunning.exchange(true)) {
        return;
    }
    std::thread(RenderLoop).detach();
}

void StopSelfTest() {
    g_selfTestRunning.store(false);
}

} // namespace mc4hos::surface
