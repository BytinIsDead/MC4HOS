/**
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import { HomeTab, GameLauncherPushBridge } from './HomeTab.ets';
import { VersionsPage } from './VersionsPage.ets';
import { ConsolePage } from './ConsolePage.ets';
import { AccountsPage } from './AccountsPage.ets';
import { SettingsPage } from './SettingsPage.ets';
import { GamePageView } from './GamePage.ets';
import { ControlsEditorPage } from './ControlsEditorPage.ets';

/**
 * Application shell: a Navigation stack whose root is a tabbed dashboard.
 * On phones the tabs collapse to a bottom bar; on tablets/2-in-1 the wide
 * layout automatically applies via adaptive GridRow columns.
 */

@Entry
@Component
struct Index {
  @Provide('nav') navStack: NavPathStack = new NavPathStack();
  @State currentIndex: number = 0;

  aboutToAppear(): void {
    GameLauncherPushBridge.bind(this.navStack);
  }

  @Builder
  PageMap(name: string) {
    if (name === 'game') {
      NavDestination() {
        GamePageView()
      }
      .hideTitleBar(true)
    } else if (name === 'controls') {
      NavDestination() {
        ControlsEditorPage()
      }
      .hideTitleBar(true)
    }
  }

  build() {
    Navigation(this.navStack) {
      Column() {
        Tabs({ barPosition: BarPosition.End, index: this.currentIndex }) {
          TabContent() {
            HomeTab()
          }
          .tabBar(this.tabItem('Home', '▶', 0))

          TabContent() {
            VersionsPage()
          }
          .tabBar(this.tabItem('Versions', '⇩', 1))

          TabContent() {
            ConsolePage()
          }
          .tabBar(this.tabItem('Console', '≡', 2))

          TabContent() {
            AccountsPage()
          }
          .tabBar(this.tabItem('Accounts', '◉', 3))

          TabContent() {
            SettingsPage()
          }
          .tabBar(this.tabItem('Settings', '⚙', 4))
        }
        .barMode(BarMode.Fixed)
        .onChange((index: number) => {
          this.currentIndex = index;
        })
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
    .navDestination(this.PageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .width('100%')
    .height('100%')
    .backgroundColor('#14181F')
  }

  @Builder
  tabItem(label: string, glyph: string, tabIndex: number) {
    Column() {
      Text(glyph)
        .fontSize(20)
        .fontColor(this.currentIndex === tabIndex ? '#63C36A' : '#8FA0B3')
      Text(label)
        .fontSize(11)
        .fontColor(this.currentIndex === tabIndex ? '#FFFFFF' : '#8FA0B3')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
