/*
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef MC4HOS_INPUT_BRIDGE_H
#define MC4HOS_INPUT_BRIDGE_H

#include "jni_compat.h"

namespace mc4hos::input {

// Action codes shared with the ArkTS overlay layer.
constexpr int ACTION_DOWN = 0;
constexpr int ACTION_UP = 1;
constexpr int ACTION_MOVE = 2;
constexpr int ACTION_CANCEL = 3;

/**
 * Queues one keyboard event (GLFW key code space) for dispatch into the
 * game through the org.mc4hos.bridge.InputBridge Java helper.
 */
void PostKey(int code, int action);

/** Queues a GLFW mouse button event. */
void PostMouseButton(int button, int action);

/** Queues a relative mouse motion (look) event. */
void PostMouseMove(float dx, float dy);

/** Queues a raw absolute touch event (pointer id, surface pixels). */
void PostTouch(int id, float x, float y, int action);

/** Marks the JVM/bridge as ready; earlier queued events are dropped. */
void SetJvmReady(bool ready);

/** Drains the queue into the Java bridge; called from the game thread. */
void DispatchPending(JNIEnv *env);

} // namespace mc4hos::input

#endif // MC4HOS_INPUT_BRIDGE_H
