/*
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#include "input_bridge.h"
#include "jni_bridge.h"
#include "log_capture.h"

#include <deque>
#include <mutex>
#include <atomic>
#include <functional>

namespace mc4hos::input {

namespace {

struct PendingEvent {
    std::function<void(JNIEnv *)> invoke;
};

std::mutex g_mutex;
std::deque<PendingEvent> g_queue;
std::atomic<bool> g_jvmReady{false};
std::atomic<int> g_dropped{0};

constexpr const char *kBridgeClass = "org/mc4hos/bridge/InputBridge";

void Enqueue(std::function<void(JNIEnv *)> fn) {
    if (!g_jvmReady.load()) {
        // No live VM to receive it (e.g. overlay touched before launch).
        g_dropped.fetch_add(1);
        return;
    }
    std::lock_guard<std::mutex> lock(g_mutex);
    g_queue.push_back(PendingEvent{std::move(fn)});
}

} // namespace

void PostKey(int code, int action) {
    Enqueue([code, action](JNIEnv *env) {
        jvalue args[2];
        args[0].i = code;
        args[1].i = action;
        jni::CallStaticVoid(env, kBridgeClass, "dispatchKey", "(II)V", args);
    });
}

void PostMouseButton(int button, int action) {
    Enqueue([button, action](JNIEnv *env) {
        jvalue args[2];
        args[0].i = button;
        args[1].i = action;
        jni::CallStaticVoid(env, kBridgeClass, "dispatchMouseButton", "(II)V", args);
    });
}

void PostMouseMove(float dx, float dy) {
    Enqueue([dx, dy](JNIEnv *env) {
        jvalue args[2];
        args[0].f = dx;
        args[1].f = dy;
        jni::CallStaticVoid(env, kBridgeClass, "dispatchMouseMove", "(FF)V", args);
    });
}

void PostTouch(int id, float x, float y, int action) {
    Enqueue([id, x, y, action](JNIEnv *env) {
        jvalue args[4];
        args[0].i = id;
        args[1].f = x;
        args[2].f = y;
        args[3].i = action;
        jni::CallStaticVoid(env, kBridgeClass, "dispatchTouch", "(IFFI)V", args);
    });
}

void SetJvmReady(bool ready) {
    g_jvmReady.store(ready);
    if (ready && g_dropped.load() > 0) {
        mc4hos::log::Emit("[MC4HOS] input bridge: dropped " +
                          std::to_string(g_dropped.load()) +
                          " overlay events sent before the VM was ready");
        g_dropped.store(0);
    }
}

void DispatchPending(JNIEnv *env) {
    if (env == nullptr || !g_jvmReady.load()) {
        return;
    }
    std::deque<PendingEvent> batch;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        batch.swap(g_queue);
    }
    for (PendingEvent &event : batch) {
        event.invoke(env);
    }
}

} // namespace mc4hos::input
