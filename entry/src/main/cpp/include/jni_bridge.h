/*
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef MC4HOS_JNI_BRIDGE_H
#define MC4HOS_JNI_BRIDGE_H

#include "jni_compat.h"
#include <string>

namespace mc4hos::jni {

/** Attach the calling (non-Java) thread; returns the env or nullptr. */
JNIEnv *AttachCurrentThread();

/** Detach after AttachCurrentThread (not required for JVM-spawned threads). */
void DetachCurrentThread();

jstring NewStringUtf(JNIEnv *env, const char *text);

bool CallStaticVoid(JNIEnv *env, const char *className, const char *method,
                    const char *signature, jvalue *args);

/** java.lang.System.exit(code) inside the embedded VM. */
void CallSystemExit(JNIEnv *env, int code);

/** Log any pending exception through the launcher pipeline. */
void ReportException(JNIEnv *env, const char *where);

} // namespace mc4hos::jni

#endif // MC4HOS_JNI_BRIDGE_H
