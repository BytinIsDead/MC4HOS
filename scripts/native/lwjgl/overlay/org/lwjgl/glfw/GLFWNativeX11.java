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

import java.nio.ByteBuffer;

public final class GLFWNativeX11 {

    private GLFWNativeX11() {
    }

    public static long glfwGetX11Display() {
        throw new UnsupportedOperationException("Not implemented");
    }

    public static long glfwGetX11Adapter(long monitor) {
        throw new UnsupportedOperationException("Not implemented");
    }

    public static long glfwGetX11Monitor(long monitor) {
        throw new UnsupportedOperationException("Not implemented");
    }

    public static long glfwGetX11Window(long window) {
        throw new UnsupportedOperationException("Not implemented");
    }

    public static void nglfwSetX11SelectionString(long string) {
        throw new UnsupportedOperationException("Not implemented");
    }

    public static void glfwSetX11SelectionString(ByteBuffer string) {
        throw new UnsupportedOperationException("Not implemented");
    }

    public static void glfwSetX11SelectionString(CharSequence string) {
        throw new UnsupportedOperationException("Not implemented");
    }

    public static long nglfwGetX11SelectionString() {
        throw new UnsupportedOperationException("Not implemented");
    }

    public static String glfwGetX11SelectionString() {
        throw new UnsupportedOperationException("Not implemented");
    }

}
