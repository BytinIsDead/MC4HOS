/*
 * OpenAL Soft derivative Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: LGPL-2.0-or-later
 * MC4HOS adaptations Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * OpenAL terms: scripts/licenses/OpenAL-COPYING.txt
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef BACKENDS_OHAUDIO_H
#define BACKENDS_OHAUDIO_H

#include "base.h"

#include <string>
#include <vector>

struct OHAudioBackendFactory final : public BackendFactory {
public:
    bool init() override;

    bool querySupport(BackendType type) override;

    std::vector<std::string> enumerate(BackendType type) override;

    BackendPtr createBackend(DeviceBase *device, BackendType type) override;

    static BackendFactory &getFactory();
};

#endif /* BACKENDS_OHAUDIO_H */
