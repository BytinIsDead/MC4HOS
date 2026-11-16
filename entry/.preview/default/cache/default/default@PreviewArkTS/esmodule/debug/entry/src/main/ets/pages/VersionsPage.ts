if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface VersionsPage_Params {
    selectedVersion?: string;
    entries?: Array<VersionEntry>;
    filterReleasesOnly?: boolean;
    statusText?: string;
    busy?: boolean;
    progressText?: string;
}
import fs from "@ohos:file.fs";
import { VersionManifestInstance } from "@normalized:N&&&entry/src/main/ets/download/VersionManifest&";
import type { VersionEntry, VersionJson } from "@normalized:N&&&entry/src/main/ets/download/VersionManifest&";
import { GameInstaller } from "@normalized:N&&&entry/src/main/ets/download/GameInstaller&";
import { DownloadManager } from "@normalized:N&&&entry/src/main/ets/download/DownloadManager&";
import { Paths } from "@normalized:N&&&entry/src/main/ets/common/Paths&";
import { KEY_SELECTED_VERSION } from "@normalized:N&&&entry/src/main/ets/common/AppState&";
export class VersionsPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__selectedVersion = this.createStorageLink(KEY_SELECTED_VERSION, '', "selectedVersion");
        this.__entries = new ObservedPropertyObjectPU([], this, "entries");
        this.__filterReleasesOnly = new ObservedPropertySimplePU(true, this, "filterReleasesOnly");
        this.__statusText = new ObservedPropertySimplePU('', this, "statusText");
        this.__busy = new ObservedPropertySimplePU(false, this, "busy");
        this.__progressText = new ObservedPropertySimplePU('', this, "progressText");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: VersionsPage_Params) {
        if (params.entries !== undefined) {
            this.entries = params.entries;
        }
        if (params.filterReleasesOnly !== undefined) {
            this.filterReleasesOnly = params.filterReleasesOnly;
        }
        if (params.statusText !== undefined) {
            this.statusText = params.statusText;
        }
        if (params.busy !== undefined) {
            this.busy = params.busy;
        }
        if (params.progressText !== undefined) {
            this.progressText = params.progressText;
        }
    }
    updateStateVars(params: VersionsPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__selectedVersion.purgeDependencyOnElmtId(rmElmtId);
        this.__entries.purgeDependencyOnElmtId(rmElmtId);
        this.__filterReleasesOnly.purgeDependencyOnElmtId(rmElmtId);
        this.__statusText.purgeDependencyOnElmtId(rmElmtId);
        this.__busy.purgeDependencyOnElmtId(rmElmtId);
        this.__progressText.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__selectedVersion.aboutToBeDeleted();
        this.__entries.aboutToBeDeleted();
        this.__filterReleasesOnly.aboutToBeDeleted();
        this.__statusText.aboutToBeDeleted();
        this.__busy.aboutToBeDeleted();
        this.__progressText.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __selectedVersion: ObservedPropertyAbstractPU<string>;
    get selectedVersion() {
        return this.__selectedVersion.get();
    }
    set selectedVersion(newValue: string) {
        this.__selectedVersion.set(newValue);
    }
    private __entries: ObservedPropertyObjectPU<Array<VersionEntry>>;
    get entries() {
        return this.__entries.get();
    }
    set entries(newValue: Array<VersionEntry>) {
        this.__entries.set(newValue);
    }
    private __filterReleasesOnly: ObservedPropertySimplePU<boolean>;
    get filterReleasesOnly() {
        return this.__filterReleasesOnly.get();
    }
    set filterReleasesOnly(newValue: boolean) {
        this.__filterReleasesOnly.set(newValue);
    }
    private __statusText: ObservedPropertySimplePU<string>;
    get statusText() {
        return this.__statusText.get();
    }
    set statusText(newValue: string) {
        this.__statusText.set(newValue);
    }
    private __busy: ObservedPropertySimplePU<boolean>;
    get busy() {
        return this.__busy.get();
    }
    set busy(newValue: boolean) {
        this.__busy.set(newValue);
    }
    private __progressText: ObservedPropertySimplePU<string>;
    get progressText() {
        return this.__progressText.get();
    }
    set progressText(newValue: string) {
        this.__progressText.set(newValue);
    }
    aboutToAppear(): void {
        VersionManifestInstance.load().then((entries: Array<VersionEntry>) => {
            this.entries = entries;
        });
        DownloadManager.subscribeProgress((label: string, received: number, total: number, finished: boolean, failed: boolean) => {
            if (finished) {
                return;
            }
            const mb: number = Math.round(received / 1048576 * 10) / 10;
            const totalMb: number = total > 0 ? Math.round(total / 1048576 * 10) / 10 : 0;
            this.progressText = totalMb > 0 ? `${label} — ${mb} / ${totalMb} MB` : `${label} — ${mb} MB`;
        });
    }
    private isInstalled(id: string): boolean {
        return fs.accessSync(Paths.clientJarPath(id));
    }
    private async download(version: VersionEntry): Promise<void> {
        if (this.busy) {
            return;
        }
        this.busy = true;
        this.statusText = `Resolving ${version.id}…`;
        try {
            const json: VersionJson | null = await VersionManifestInstance.fetchVersion(version.id);
            if (json === null) {
                this.statusText = `Could not resolve ${version.id}`;
                this.busy = false;
                return;
            }
            this.statusText = `Downloading ${version.id}…`;
            const okFiles: boolean = await GameInstaller.ensureInstalled(json, (p) => {
                this.progressText = `${p.current} / ${p.total} — ${p.currentFile}`;
            });
            const assets: string = okFiles ? await GameInstaller.ensureAssets(json, (p) => {
                this.progressText = `assets ${p.current} / ${p.total}`;
            }) : '';
            if (okFiles && assets.length > 0) {
                this.selectedVersion = version.id;
                this.statusText = `${version.id} installed and selected`;
            }
            else {
                this.statusText = `Download incomplete for ${version.id}`;
            }
        }
        catch (err) {
            const e = err as Error;
            this.statusText = `Error: ${e.message}`;
        }
        this.busy = false;
        this.progressText = '';
    }
    private typeColor(type: string): string {
        if (type === 'release') {
            return '#63C36A';
        }
        if (type === 'snapshot') {
            return '#D9A94E';
        }
        return '#8FA0B3';
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/VersionsPage.ets(98:5)", "entry");
            Column.width('100%');
            Column.height('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/VersionsPage.ets(99:7)", "entry");
            Row.width('100%');
            Row.padding({ left: 16, right: 16, top: 12, bottom: 8 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Versions');
            Text.debugLine("entry/src/main/ets/pages/VersionsPage.ets(100:9)", "entry");
            Text.fontSize(18);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor('#FFFFFF');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/VersionsPage.ets(104:9)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Toggle.create({ type: ToggleType.Checkbox, isOn: this.filterReleasesOnly });
            Toggle.debugLine("entry/src/main/ets/pages/VersionsPage.ets(105:9)", "entry");
            Toggle.onChange((isOn: boolean) => {
                this.filterReleasesOnly = isOn;
            });
        }, Toggle);
        Toggle.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('releases only');
            Text.debugLine("entry/src/main/ets/pages/VersionsPage.ets(109:9)", "entry");
            Text.fontSize(11);
            Text.fontColor('#8FA0B3');
        }, Text);
        Text.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.statusText.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.statusText);
                        Text.debugLine("entry/src/main/ets/pages/VersionsPage.ets(117:9)", "entry");
                        Text.fontSize(12);
                        Text.fontColor('#5FA8D3');
                        Text.width('100%');
                        Text.padding({ left: 16, right: 16, bottom: 4 });
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.progressText.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.progressText);
                        Text.debugLine("entry/src/main/ets/pages/VersionsPage.ets(124:9)", "entry");
                        Text.fontSize(11);
                        Text.fontColor('#8FA0B3');
                        Text.width('100%');
                        Text.padding({ left: 16, right: 16, bottom: 4 });
                        Text.maxLines(1);
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            List.create({ space: 6 });
            List.debugLine("entry/src/main/ets/pages/VersionsPage.ets(132:7)", "entry");
            List.layoutWeight(1);
            List.width('100%');
        }, List);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const entry = _item;
                {
                    const itemCreation = (elmtId, isInitialRender) => {
                        ViewStackProcessor.StartGetAccessRecordingFor(elmtId);
                        ListItem.create(deepRenderFunction, true);
                        if (!isInitialRender) {
                            ListItem.pop();
                        }
                        ViewStackProcessor.StopGetAccessRecording();
                    };
                    const itemCreation2 = (elmtId, isInitialRender) => {
                        ListItem.create(deepRenderFunction, true);
                        ListItem.debugLine("entry/src/main/ets/pages/VersionsPage.ets(135:11)", "entry");
                    };
                    const deepRenderFunction = (elmtId, isInitialRender) => {
                        itemCreation(elmtId, isInitialRender);
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            Row.create();
                            Row.debugLine("entry/src/main/ets/pages/VersionsPage.ets(136:13)", "entry");
                            Row.width('100%');
                            Row.padding({ left: 16, right: 16, top: 8, bottom: 8 });
                            Row.borderRadius(8);
                            Row.backgroundColor('#1F2430');
                        }, Row);
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            Column.create();
                            Column.debugLine("entry/src/main/ets/pages/VersionsPage.ets(137:15)", "entry");
                            Column.alignItems(HorizontalAlign.Start);
                            Column.layoutWeight(1);
                        }, Column);
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            Text.create(entry.id);
                            Text.debugLine("entry/src/main/ets/pages/VersionsPage.ets(138:17)", "entry");
                            Text.fontSize(15);
                            Text.fontColor('#FFFFFF');
                        }, Text);
                        Text.pop();
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            Text.create(`${entry.type} · ${entry.releaseTime.substring(0, 10)}`);
                            Text.debugLine("entry/src/main/ets/pages/VersionsPage.ets(141:17)", "entry");
                            Text.fontSize(11);
                            Text.fontColor(this.typeColor(entry.type));
                        }, Text);
                        Text.pop();
                        Column.pop();
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            If.create();
                            if (this.isInstalled(entry.id)) {
                                this.ifElseBranchUpdateFunction(0, () => {
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Text.create(this.selectedVersion === entry.id ? 'ACTIVE' : 'installed');
                                        Text.debugLine("entry/src/main/ets/pages/VersionsPage.ets(149:17)", "entry");
                                        Text.fontSize(11);
                                        Text.fontColor(this.selectedVersion === entry.id ? '#63C36A' : '#8FA0B3');
                                        Text.margin({ right: 8 });
                                    }, Text);
                                    Text.pop();
                                });
                            }
                            else {
                                this.ifElseBranchUpdateFunction(1, () => {
                                });
                            }
                        }, If);
                        If.pop();
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            Button.createWithLabel(this.isInstalled(entry.id) ? 'Re-fetch' : 'Install');
                            Button.debugLine("entry/src/main/ets/pages/VersionsPage.ets(154:15)", "entry");
                            Button.height(32);
                            Button.fontSize(12);
                            Button.backgroundColor('#2A3340');
                            Button.enabled(!this.busy);
                            Button.onClick(() => {
                                this.download(entry);
                            });
                        }, Button);
                        Button.pop();
                        Row.pop();
                        ListItem.pop();
                    };
                    this.observeComponentCreation2(itemCreation2, ListItem);
                    ListItem.pop();
                }
            };
            this.forEachUpdateFunction(elmtId, this.entries.filter((e: VersionEntry) => !this.filterReleasesOnly || e.type === 'release'), forEachItemGenFunction, (entry: VersionEntry) => entry.id, false, false);
        }, ForEach);
        ForEach.pop();
        List.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
