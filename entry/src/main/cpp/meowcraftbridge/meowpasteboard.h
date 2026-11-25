/*
 * Original bridge Copyright (c) 2026 Harmomeow Craft Launcher contributors
 * SPDX-License-Identifier: MIT
 * MC4HOS adaptations Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * Original bridge terms: scripts/licenses/Harmomeow-LICENSE.txt
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef MEOWCRAFTBRIDGE_MEOWPASTEBOARD_H
#define MEOWCRAFTBRIDGE_MEOWPASTEBOARD_H

/*
 * Clipboard write through the platform pasteboard NDK.
 *
 * MC copies text from a few screens (the "copy link" buttons). On the GLFW path that
 * reaches the bridge through CallbackBridge.nativeClipboard, on the SDL path through the
 * ohos driver's SetClipboardText hook; both end up here.
 *
 * Returns 0 on success, -1 on failure (the NDK is resolved at run time; see the .c file).
 */
int meow_clipboard_set_text(const char *utf8);

#endif /* MEOWCRAFTBRIDGE_MEOWPASTEBOARD_H */
