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

public final class GLFWNativeWGL {

    private GLFWNativeWGL() {
    }

    public static long glfwGetWGLContext(long window) {
        throw new UnsupportedOperationException("Not implemented");
    }

    public static void setPath(FunctionProvider provider) {
        throw new UnsupportedOperationException("Not implemented");
    }

    public static void setPath(String path) {
        throw new UnsupportedOperationException("Not implemented");
    }

}
