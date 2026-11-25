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

import java.util.HashMap;
import java.util.Map;

public class GLFWWindowProperties {

    public int width = GLFW.mGLFWWindowWidth;
    public int height = GLFW.mGLFWWindowHeight;
    public int x;
    public int y;
    public CharSequence title;
    public boolean shouldClose;
    public boolean isInitialSizeCalled;
    public boolean isCursorEntered;
    public Map<Integer, Integer> inputModes = new HashMap<>();
    public Map<Integer, Integer> windowAttribs = new HashMap<>();

}
