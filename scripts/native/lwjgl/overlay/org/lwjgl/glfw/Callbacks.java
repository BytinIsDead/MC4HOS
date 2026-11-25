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

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;

import org.lwjgl.system.Checks;

public final class Callbacks {

    private Callbacks() {
    }

    public static void glfwFreeCallbacks(long window) {
        if (Checks.CHECKS) {
            Checks.check(window);
        }

        try {
            for (Method method : GLFW.class.getMethods()) {
                String name = method.getName();
                if (!name.startsWith("glfwSet") || !name.endsWith("Callback")) {
                    continue;
                }
                int parameters = method.getParameterCount();
                if (parameters == 1) {
                    method.invoke(null, (Object) null);
                } else if (parameters == 2) {
                    method.invoke(null, GLFW.glfwGetCurrentContext(), null);
                }
            }
        } catch (IllegalAccessException | NullPointerException e) {
            throw new RuntimeException(
                    "org.lwjgl.glfw.GLFW.glfwSetXXXCallback() must be public and static", e);
        } catch (InvocationTargetException e) {
            throw new RuntimeException(e);
        }
    }

}
