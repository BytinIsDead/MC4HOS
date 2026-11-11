/*
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#include "jni_bridge.h"
#include "jvm_loader.h"
#include "log_capture.h"

namespace mc4hos::jni {

JNIEnv *AttachCurrentThread() {
    JavaVM *vm = static_cast<JavaVM *>(jvm::GetGlobalJavaVM());
    if (vm == nullptr) {
        return nullptr;
    }
    JNIEnv *env = nullptr;
    jint status = vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_8);
    if (status == JNI_OK) {
        return env;
    }
    if (status == JNI_EDETACHED) {
        void *attachEnv = nullptr;
        if (vm->AttachCurrentThread(&attachEnv, nullptr) == JNI_OK) {
            return static_cast<JNIEnv *>(attachEnv);
        }
    }
    return nullptr;
}

void DetachCurrentThread() {
    JavaVM *vm = static_cast<JavaVM *>(jvm::GetGlobalJavaVM());
    if (vm != nullptr) {
        vm->DetachCurrentThread();
    }
}

jstring NewStringUtf(JNIEnv *env, const char *text) {
    if (env == nullptr || text == nullptr) {
        return nullptr;
    }
    return env->NewStringUTF(text);
}

bool CallStaticVoid(JNIEnv *env, const char *className, const char *method,
                    const char *signature, jvalue *args) {
    if (env == nullptr) {
        return false;
    }
    jclass cls = env->FindClass(className);
    if (cls == nullptr) {
        ReportException(env, "FindClass");
        return false;
    }
    jmethodID mid = env->GetStaticMethodID(cls, method, signature);
    if (mid == nullptr) {
        ReportException(env, "GetStaticMethodID");
        env->DeleteLocalRef(cls);
        return false;
    }
    env->CallStaticVoidMethodA(cls, mid, args);
    bool ok = !env->ExceptionCheck();
    if (!ok) {
        ReportException(env, method);
    }
    env->DeleteLocalRef(cls);
    return ok;
}

void CallSystemExit(JNIEnv *env, int code) {
    jvalue args[1];
    args[0].i = code;
    if (!CallStaticVoid(env, "java/lang/System", "exit", "(I)V", args)) {
        mc4hos::log::Emit("[MC4HOS] System.exit() call failed; VM may still be running");
    }
}

void ReportException(JNIEnv *env, const char *where) {
    if (env == nullptr || !env->ExceptionCheck()) {
        return;
    }
    jthrowable throwable = env->ExceptionOccurred();
    env->ExceptionClear();
    if (throwable == nullptr) {
        return;
    }
    jclass cls = env->GetObjectClass(throwable);
    jmethodID toString = env->GetMethodID(cls, "toString", "()Ljava/lang/String;");
    if (toString != nullptr) {
        auto message = static_cast<jstring>(env->CallObjectMethod(throwable, toString));
        if (message != nullptr) {
            const char *chars = env->GetStringUTFChars(message, nullptr);
            if (chars != nullptr) {
                mc4hos::log::Emit(std::string("[MC4HOS] JNI exception at ") + where + ": " + chars);
                env->ReleaseStringUTFChars(message, chars);
            }
            env->DeleteLocalRef(message);
        }
    }
    env->DeleteLocalRef(cls);
    env->DeleteLocalRef(throwable);
}

} // namespace mc4hos::jni
