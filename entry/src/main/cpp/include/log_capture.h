/*
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef MC4HOS_LOG_CAPTURE_H
#define MC4HOS_LOG_CAPTURE_H

#include <functional>
#include <string>

namespace mc4hos::log {

/**
 * Captures process stdout/stderr (which the embedded JVM and the game use
 * for their console output) into the launcher log file and forwards every
 * line to the ArkTS console through the registered sink.
 */
void Install(const std::string &logDir, std::function<void(const char *)> sink);

/** Routes a launcher-internal message through the same pipeline. */
void Emit(const std::string &line);

} // namespace mc4hos::log

#endif // MC4HOS_LOG_CAPTURE_H
