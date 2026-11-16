<!--
Copyright (C) 2026 MC4HOS Contributors
SPDX-License-Identifier: MPL-2.0-no-copyleft-exception

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
-->

## What

<!-- One or two sentences describing the change. -->

## Why

<!-- Link the issue, or explain the motivation. -->

## Checklist

- [ ] New/changed source files carry
      `SPDX-License-Identifier: MPL-2.0-no-copyleft-exception`
- [ ] `python3 scripts/check_mpl_headers.py` passes
- [ ] `python3 scripts/check_configs.py` passes
- [ ] No GPL-licensed material introduced; third-party runtime components
      stay build-from-upstream and are documented in NOTICE.md
- [ ] Native changes considered for **both** ABIs (arm64-v8a, x86_64)
- [ ] No game assets or proprietary code added to the repository
- [ ] `resources/**/*.json` / `profile/*.json` remain comment-free strict JSON
