/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Copies entry/src/main/ets/core/**.ets into tests/.build/core as .ts so
 * Node can execute the pure core with its native type stripping. Relative
 * imports are rewritten to carry the .ts extension.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const srcRoot = path.resolve(here, '../../entry/src/main/ets/core');
const buildRoot = path.resolve(here, '../.build');
const outRoot = path.join(buildRoot, 'core');

fs.rmSync(buildRoot, { recursive: true, force: true });
fs.mkdirSync(outRoot, { recursive: true });
fs.writeFileSync(path.join(buildRoot, 'package.json'), '{"type":"module"}\n');

function walk(dir) {
  const out = [];
  for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, item.name);
    if (item.isDirectory()) {
      out.push(...walk(full));
    } else if (item.name.endsWith('.ets')) {
      out.push(full);
    }
  }
  return out;
}

const files = walk(srcRoot);
for (const file of files) {
  const rel = path.relative(srcRoot, file).replace(/\.ets$/, '.ts');
  const target = path.join(outRoot, rel);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const source = fs.readFileSync(file, 'utf8');
  const rewritten = source.replace(
    /(from\s+['"])(\.{1,2}\/[^'"]+)(['"])/g,
    (match, prefix, spec, suffix) =>
      spec.endsWith('.ts') ? match : `${prefix}${spec}.ts${suffix}`
  );
  fs.writeFileSync(target, rewritten);
}

console.log(`core: ${files.length} module(s) -> ${path.relative(process.cwd(), outRoot)}`);
