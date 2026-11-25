# Copyright (c) 2026 Harmomeow Craft Launcher contributors
# SPDX-License-Identifier: MIT
# MC4HOS adaptations Copyright (C) 2026 MC4HOS Contributors
# SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
#
# Original terms: scripts/licenses/Harmomeow-LICENSE.txt
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.lwjgl.glfw;

import org.lwjgl.system.FunctionProvider;

public final class GLFWNativeEGL {

    private GLFWNativeEGL() {
    }

    public static long glfwGetEGLDisplay() {
        throw new UnsupportedOperationException("Not implemented");
    }

    public static long glfwGetEGLContext(long window) {
        throw new UnsupportedOperationException("Not implemented");
    }

    public static long glfwGetEGLSurface(long window) {
        throw new UnsupportedOperationException("Not implemented");
    }

    public static long glfwGetEGLConfig(long window) {
        throw new UnsupportedOperationException("Not implemented");
    }

    public static void setEGLPath(FunctionProvider provider) {
        throw new UnsupportedOperationException("Not implemented");
    }

    public static void setEGLPath(String path) {
        throw new UnsupportedOperationException("Not implemented");
    }

    public static void setGLESPath(FunctionProvider provider) {
        throw new UnsupportedOperationException("Not implemented");
    }

    public static void setGLESPath(String path) {
        throw new UnsupportedOperationException("Not implemented");
    }

}
