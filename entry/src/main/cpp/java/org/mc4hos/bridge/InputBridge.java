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
 * Clean-room Java-side input relay for MC4HOS.
 *
 * The native layer (libmc4hos_core.so) calls these static methods with
 * virtual-overlay input; a LWJGL-compatible input backend (built separately
 * for OpenHarmony, see docs/NATIVES.md) reads the queued state and feeds the
 * game. GLFW key codes are the canonical scancode space.
 *
 * This class contains no third-party code and ships as mc4hos-bridge.jar on
 * the game classpath.
 */
public final class InputBridge {

    /** Touch action codes (mirrors the native layer). */
    public static final int ACTION_DOWN = 0;
    public static final int ACTION_UP = 1;
    public static final int ACTION_MOVE = 2;
    public static final int ACTION_CANCEL = 3;

    private static final int QUEUE_CAPACITY = 256;

    /** GLFW key events: {code, action} pairs, oldest first. */
    private static final int[] KEY_QUEUE = new int[QUEUE_CAPACITY * 2];
    private static volatile int keyHead = 0;
    private static volatile int keyTail = 0;

    /** GLFW mouse button events: {button, action} pairs. */
    private static final int[] MOUSE_BUTTON_QUEUE = new int[QUEUE_CAPACITY * 2];
    private static volatile int mouseHead = 0;
    private static volatile int mouseTail = 0;

    /** Relative mouse motion, accumulated between backend polls. */
    private static final Object MOVE_LOCK = new Object();
    private static float pendingMoveX = 0f;
    private static float pendingMoveY = 0f;

    /** Guards both ring buffers. */
    private static final Object QUEUE_LOCK = new Object();

    /** Latest absolute touch state: {id, x, y, action} per slot. */
    private static final float[] TOUCH_STATE = new float[QUEUE_CAPACITY * 4];
    private static final Object TOUCH_LOCK = new Object();

    private static volatile boolean initialized = false;

    private InputBridge() {
    }

    /** Called by the native layer once the JVM is up. */
    public static void markInitialized() {
        initialized = true;
        System.out.println("[MC4HOS] InputBridge ready (keycode space: GLFW)");
    }

    public static boolean isInitialized() {
        return initialized;
    }

    // -----------------------------------------------------------------
    // native entry points (invoked from libmc4hos_core.so)
    // -----------------------------------------------------------------

    public static void dispatchKey(int code, int action) {
        enqueue(KEY_QUEUE, true, code, action);
    }

    public static void dispatchMouseButton(int button, int action) {
        enqueue(MOUSE_BUTTON_QUEUE, false, button, action);
    }

    public static void dispatchMouseMove(float dx, float dy) {
        synchronized (MOVE_LOCK) {
            pendingMoveX += dx;
            pendingMoveY += dy;
        }
    }

    public static void dispatchTouch(int id, float x, float y, int action) {
        int slot = Math.floorMod(id, QUEUE_CAPACITY) * 4;
        synchronized (TOUCH_LOCK) {
            TOUCH_STATE[slot] = id;
            TOUCH_STATE[slot + 1] = x;
            TOUCH_STATE[slot + 2] = y;
            TOUCH_STATE[slot + 3] = action;
        }
    }

    // -----------------------------------------------------------------
    // backend polling API (consumed by the LWJGL-compat input backend)
    // -----------------------------------------------------------------

    /** Pairs of {code, action}; returns the number of pairs consumed. */
    public static int pollKeys(int[] out) {
        return drain(KEY_QUEUE, true, out);
    }

    /** Pairs of {button, action}; returns the number of pairs consumed. */
    public static int pollMouseButtons(int[] out) {
        return drain(MOUSE_BUTTON_QUEUE, false, out);
    }

    /** Returns and clears accumulated relative motion. */
    public static float[] consumeMouseDelta() {
        synchronized (MOVE_LOCK) {
            float[] delta = new float[] { pendingMoveX, pendingMoveY };
            pendingMoveX = 0f;
            pendingMoveY = 0f;
            return delta;
        }
    }

    /** Snapshot of the active touch slots (4 floats per pointer). */
    public static float[] touchState() {
        synchronized (TOUCH_LOCK) {
            return TOUCH_STATE.clone();
        }
    }

    // -----------------------------------------------------------------

    private static void enqueue(int[] queue, boolean keys, int a, int b) {
        synchronized (QUEUE_LOCK) {
            int head = keys ? keyHead : mouseHead;
            int tail = keys ? keyTail : mouseTail;
            int next = (tail + 2 >= queue.length) ? 0 : tail + 2;
            if (next == head) {
                return; // full: drop newest
            }
            queue[tail] = a;
            queue[tail + 1] = b;
            if (keys) {
                keyTail = next;
            } else {
                mouseTail = next;
            }
        }
    }

    private static int drain(int[] queue, boolean keys, int[] out) {
        synchronized (QUEUE_LOCK) {
            int head = keys ? keyHead : mouseHead;
            int tail = keys ? keyTail : mouseTail;
            int count = 0;
            while (head != tail && count + 2 <= out.length) {
                out[count] = queue[head];
                out[count + 1] = queue[head + 1];
                count += 2;
                head += 2;
                if (head >= queue.length) {
                    head = 0;
                }
            }
            if (keys) {
                keyHead = head;
            } else {
                mouseHead = head;
            }
            return count / 2;
        }
    }
}
