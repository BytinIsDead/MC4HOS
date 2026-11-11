/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/**
 * ArkTS-safe JSON access helpers.
 *
 * ArkTS forbids `any` and index-signature interfaces, so parsed documents are
 * handled as `Record<string, Object>` and read through these typed accessors
 * instead of unchecked casts. Every accessor tolerates missing keys and wrong
 * types, returning the caller-provided default instead of throwing.
 */

export type JsonObj = Record<string, Object>;

export function parseJson(text: string): JsonObj | null {
  try {
    const raw: Object | null = JSON.parse(text) as Object;
    if (raw === null || raw === undefined || typeof raw !== 'object' || Array.isArray(raw)) {
      return null;
    }
    return raw as JsonObj;
  } catch (e) {
    return null;
  }
}

export function asObj(value: Object | null | undefined): JsonObj | null {
  if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  return value as JsonObj;
}

export function asArray(value: Object | null | undefined): Array<Object> | null {
  if (value === null || value === undefined || !Array.isArray(value)) {
    return null;
  }
  return value as Array<Object>;
}

export function getStr(obj: JsonObj, key: string, def: string = ''): string {
  const v: Object | undefined = obj[key];
  if (v === null || v === undefined || typeof v !== 'string') {
    return def;
  }
  return v as string;
}

export function getNum(obj: JsonObj, key: string, def: number = 0): number {
  const v: Object | undefined = obj[key];
  if (v === null || v === undefined || typeof v !== 'number') {
    return def;
  }
  return v as number;
}

export function getBool(obj: JsonObj, key: string, def: boolean = false): boolean {
  const v: Object | undefined = obj[key];
  if (v === null || v === undefined || typeof v !== 'boolean') {
    return def;
  }
  return v as boolean;
}

export function getObj(obj: JsonObj, key: string): JsonObj | null {
  return asObj(obj[key]);
}

export function getArr(obj: JsonObj, key: string): Array<Object> | null {
  return asArray(obj[key]);
}
