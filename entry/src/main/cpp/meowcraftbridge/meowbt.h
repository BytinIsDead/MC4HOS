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

/*
 * meowbt.h - native crash backtrace dumper (diagnostic).
 *
 * meow_bt_install_once() installs SIGSEGV/SIGBUS/SIGABRT handlers that print a
 * native backtrace to stderr (redirected to the JVM log pipe -> hilog) and then
 * chain to the previously installed handler, so the JVM's crash semantics are
 * unchanged. Enabled only when MEOW_BT is set. Install from a thread that runs
 * after the JVM is up (the bridge render thread), since HotSpot installs its
 * own SIGSEGV handler during startup.
 */
#ifndef MEOWCRAFTBRIDGE_MEOWBT_H
#define MEOWCRAFTBRIDGE_MEOWBT_H

#ifdef __cplusplus
extern "C" {
#endif

void meow_bt_install_once(void);

#ifdef __cplusplus
}
#endif

#endif /* MEOWCRAFTBRIDGE_MEOWBT_H */
