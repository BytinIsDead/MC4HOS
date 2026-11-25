/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/**
 * License overview for the launcher and everything it loads or downloads.
 * Full texts live in the source tree (LICENSE, NOTICE.md) and in the bundled
 * runtime notices; game natives are built separately, never committed.
 */

interface LicenseEntry {
  name: string;
  license: string;
  detail: string;
}

interface LicenseSection {
  title: string;
  entries: Array<LicenseEntry>;
}

const SECTIONS: Array<LicenseSection> = [
  {
    title: 'This application',
    entries: [
      {
        name: 'MC4HOS launcher',
        license: 'MPL-2.0',
        detail: 'MPL-2.0 with Exhibit B appended (SPDX: MPL-2.0-no-copyleft-exception). ' +
          'Covered files stay MPL-2.0; downstream works may not combine them with ' +
          'Secondary-License code. Source is available with every distributed build; ' +
          'modified files must keep the Exhibit A notice. Provided without warranty.'
      }
    ]
  },
  {
    title: 'Runtime components',
    entries: [
      {
        name: 'OpenJDK',
        license: 'GPLv2 + Classpath Exception',
        detail: 'OpenHarmony builds for aarch64 (Java 8/17/21/25) and x86_64 ' +
          '(Java 21/25). Loaded in-process through JNI; the Classpath Exception permits ' +
          'linking independent modules with the JDK. aarch64 packs ship inside the app; ' +
          'builds with bundled runtimes carry the full GPLv2+CE text ' +
          '(jvm/OpenJDK-LICENSE.txt) and a per-pack source notice ' +
          '(jvm/RUNTIME-NOTICES.txt), both copied into the extracted runtime. ' +
          'The JDK8 pack also keeps its upstream LICENSE.'
      },
      {
        name: 'LWJGL',
        license: 'BSD-3-Clause',
        detail: 'Window, input, OpenGL, GLFW and OpenAL bindings for Minecraft ' +
          '(liblwjgl_343*.so, liblwjgl_tinyfd.so), built from upstream sources per ABI.'
      },
      {
        name: 'OpenAL Soft',
        license: 'LGPL-2.0-or-later',
        detail: 'Audio backend (libopenal.so), built from upstream sources and ' +
          'dynamically loaded by the game.'
      },
      {
        name: 'gl4es',
        license: 'MIT',
        detail: 'Optional desktop-GL to GLES translation layer. It is not ' +
          'included in this HAP; the game path requires system desktop OpenGL.'
      },
      {
        name: 'HarmonyOS / OpenHarmony SDK',
        license: 'Apache-2.0 (LLVM exception)',
        detail: 'libc++_shared.so, the native SDK NOTICE and related toolchain ' +
          'components shipped with runtime packs and the HAP.'
      }
    ]
  },
  {
    title: 'Game content and services',
    entries: [
      {
        name: 'Minecraft: Java Edition',
        license: 'Proprietary (not included)',
        detail: 'No game assets, jars or libraries are bundled. The launcher ' +
          'downloads official files from Mojang servers for an authenticated account ' +
          'the user has purchased. The Minecraft EULA applies to gameplay.'
      },
      {
        name: 'Microsoft / Xbox Live',
        license: 'Proprietary (not included)',
        detail: 'Authentication uses the official OAuth device-code and Minecraft ' +
          'services endpoints. No Microsoft code is bundled or modified.'
      },
      {
        name: 'Mojang trademark',
        license: 'Trademark notice',
        detail: 'Minecraft is a trademark of Mojang Synergies AB. MC4HOS is not ' +
          'affiliated with Mojang, Microsoft, or OpenHarmony/Huawei.'
      }
    ]
  }
];

const SOURCE_NOTE: string =
  'Full license texts ship with the source distribution: LICENSE and NOTICE.md at ' +
  'the repository root, plus each runtime pack\'s license files and source notice. ' +
  'Bundled OpenJDK runtimes are redistributed under GPLv2 + Classpath Exception and ' +
  'can be replaced by installing a different runtime pack; game-native binaries ' +
  '(LWJGL, OpenAL) are built separately and are not committed to this repository.';

@Component
export struct LicensesPage {
  build() {
    Column() {
      Text('Licenses')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Scroll() {
        Column({ space: 12 }) {
          ForEach(SECTIONS, (section: LicenseSection) => {
            Column() {
              Text(section.title)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#9FB6CD')
                .width('100%')
              ForEach(section.entries, (entry: LicenseEntry) => {
                Column() {
                  Row() {
                    Text(entry.name)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor('#FFFFFF')
                      .layoutWeight(1)
                    Text(entry.license)
                      .fontSize(11)
                      .fontColor('#63C36A')
                      .maxLines(2)
                      .textAlign(TextAlign.End)
                      .margin({ left: 8 })
                  }
                  .width('100%')
                  Text(entry.detail)
                    .fontSize(12)
                    .fontColor('#8FA0B3')
                    .lineHeight(17)
                    .margin({ top: 6 })
                    .width('100%')
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
                .padding(12)
                .borderRadius(8)
                .backgroundColor('#1A1F27')
                .margin({ top: 8 })
              }, (entry: LicenseEntry) => entry.name)
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }, (section: LicenseSection) => section.title)

          Text(SOURCE_NOTE)
            .fontSize(11)
            .fontColor('#8FA0B3')
            .lineHeight(16)
            .width('100%')
            .padding(12)
            .borderRadius(8)
            .backgroundColor('#14181F')
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
