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
 * meowlog.h - hilog helpers for libmeowcraftbridge.so.
 *
 * A tiny wrapper around OH_LOG_Print with a single domain/tag so that native
 * bridge logs are easy to filter. The tag is MeowCraft to keep these messages
 * distinct from other native components in the process.
 */
#ifndef MEOWCRAFTBRIDGE_MEOWLOG_H
#define MEOWCRAFTBRIDGE_MEOWLOG_H

#include "hilog/log.h"

#define MEOW_LOG_DOMAIN 0xD003
#define MEOW_LOG_TAG "MeowCraft"

#define MEOWLOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, MEOW_LOG_DOMAIN, MEOW_LOG_TAG, __VA_ARGS__)
#define MEOWLOGW(...) OH_LOG_Print(LOG_APP, LOG_WARN, MEOW_LOG_DOMAIN, MEOW_LOG_TAG, __VA_ARGS__)
#define MEOWLOGE(...) OH_LOG_Print(LOG_APP, LOG_ERROR, MEOW_LOG_DOMAIN, MEOW_LOG_TAG, __VA_ARGS__)
#define MEOWLOGD(...) OH_LOG_Print(LOG_APP, LOG_DEBUG, MEOW_LOG_DOMAIN, MEOW_LOG_TAG, __VA_ARGS__)

#endif /* MEOWCRAFTBRIDGE_MEOWLOG_H */
