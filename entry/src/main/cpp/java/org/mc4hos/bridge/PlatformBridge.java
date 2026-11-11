/*
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

package org.mc4hos.bridge;

/**
 * Clean-room platform handshake for MC4HOS: receives HarmonyOS surface
 * metadata from the native layer and provides environment descriptors to
 * the game-side compatibility stack via system properties (set by the
 * launcher: mc4hos.natives.dir, mc4hos.game.dir, mc4hos.assets.dir).
 */
public final class PlatformBridge {

    private static volatile int surfaceWidth = 0;
    private static volatile int surfaceHeight = 0;
    private static volatile boolean surfaceReady = false;

    private PlatformBridge() {
    }

    /**
     * Invoked by libmc4hos_core.so right after VM creation with the current
     * XComponent surface dimensions (physical pixels).
     */
    public static void onGameSurfaceCreated(int width, int height) {
        surfaceWidth = width;
        surfaceHeight = height;
        surfaceReady = true;
        if (!InputBridge.isInitialized()) {
            InputBridge.markInitialized();
        }
        System.out.println("[MC4HOS] PlatformBridge: surface " + width + "x" + height);
    }

    public static boolean isSurfaceReady() {
        return surfaceReady;
    }

    public static int surfaceWidth() {
        return surfaceWidth;
    }

    public static int surfaceHeight() {
        return surfaceHeight;
    }

    /** Convenience accessor for the launcher-provided natives directory. */
    public static String nativesDir() {
        return System.getProperty("mc4hos.natives.dir", "");
    }

    /** Convenience accessor for the launcher-provided game directory. */
    public static String gameDir() {
        return System.getProperty("mc4hos.game.dir", "");
    }
}
