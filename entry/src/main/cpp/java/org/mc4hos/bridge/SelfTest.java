/*
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

package org.mc4hos.bridge;

/**
 * JVM self-test entry point — launched by the launcher's self-test mode in
 * place of the game. Validates, without any Mojang services or account:
 * the embedded JVM boots, JNI invocation reaches Java, the bridge jar is on
 * the classpath, launcher-provided system properties and surface metadata
 * are visible, and the Java-side input bridge initializes.
 *
 * Compiled into mc4hos-bridge.jar (docs/NATIVES.md §3).
 */
public final class SelfTest {

    private SelfTest() {
    }

    public static void main(String[] args) {
        System.out.println("[MC4HOS] JVM self-test: booted OK");
        System.out.println("[MC4HOS] java.version  = " + System.getProperty("java.version"));
        System.out.println("[MC4HOS] java.home     = " + System.getProperty("java.home"));
        System.out.println("[MC4HOS] natives.dir   = " + PlatformBridge.nativesDir());
        System.out.println("[MC4HOS] game.dir      = " + PlatformBridge.gameDir());
        if (PlatformBridge.isSurfaceReady()) {
            System.out.println("[MC4HOS] surface       = " + PlatformBridge.surfaceWidth()
                    + "x" + PlatformBridge.surfaceHeight());
        } else {
            System.out.println("[MC4HOS] surface       = not yet created (game view closed)");
        }
        InputBridge.markInitialized();
        System.out.println("[MC4HOS] JVM self-test: PASS");
    }
}
