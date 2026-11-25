/*
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef MC4HOS_GAME_SURFACE_H
#define MC4HOS_GAME_SURFACE_H

#include <cstdint>
#include <string>
#include <vector>

struct OH_NativeXComponent;

namespace mc4hos::surface {

// XComponent lifecycle entry points (invoked from napi_init registration).
void OnSurfaceCreated(OH_NativeXComponent *component, void *window);
void OnSurfaceChanged(OH_NativeXComponent *component, void *window);
void OnSurfaceDestroyed(OH_NativeXComponent *component, void *window);
void DispatchTouchEvent(OH_NativeXComponent *component, void *window);

void *NativeWindow();
uint32_t SurfaceWidth();
uint32_t SurfaceHeight();

bool LoadNativeBridge(const std::vector<std::string> &nativeDirs);
void PublishNativeWindow();
void ForwardKey(int code, int action);
void ForwardMouseButton(int button, int action);
void ForwardMouseMove(float dx, float dy);
void ForwardTouch(int id, float x, float y, int action);

/**
 * Self-test renderer: a spinning triangle on a private EGL/GLES3 context,
 * used to verify the XComponent → EGLNativeWindow pipeline without the JVM.
 */
void StartSelfTest();
void StopSelfTest();

} // namespace mc4hos::surface

#endif // MC4HOS_GAME_SURFACE_H
