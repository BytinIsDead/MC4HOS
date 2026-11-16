if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface HomeTab_Params {
    selectedVersion?: string;
    ramMb?: number;
    accountName?: string;
    accountReady?: boolean;
    selfTestMode?: boolean;
    versions?: Array<VersionEntry>;
    progress?: LaunchProgress;
    launching?: boolean;
    navStack?: NavPathStack | null;
}
import { VersionManifestInstance } from "@normalized:N&&&entry/src/main/ets/download/VersionManifest&";
import type { VersionEntry } from "@normalized:N&&&entry/src/main/ets/download/VersionManifest&";
import { GameLauncher } from "@normalized:N&&&entry/src/main/ets/launch/GameLauncher&";
import type { LaunchProgress } from "@normalized:N&&&entry/src/main/ets/launch/GameLauncher&";
import { KEY_SELECTED_VERSION, KEY_RAM_MB, KEY_ACCOUNT_NAME, KEY_ACCOUNT_READY, KEY_DEMO_MODE, clampRam, maxDeviceRamMb } from "@normalized:N&&&entry/src/main/ets/common/AppState&";
export class HomeTab extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__selectedVersion = this.createStorageLink(KEY_SELECTED_VERSION, '', "selectedVersion");
        this.__ramMb = this.createStorageLink(KEY_RAM_MB, 2048, "ramMb");
        this.__accountName = this.createStorageLink(KEY_ACCOUNT_NAME, '', "accountName");
        this.__accountReady = this.createStorageLink(KEY_ACCOUNT_READY, false, "accountReady");
        this.__selfTestMode = this.createStorageLink(KEY_DEMO_MODE, false, "selfTestMode");
        this.__versions = new ObservedPropertyObjectPU([], this, "versions");
        this.__progress = new ObservedPropertyObjectPU({ phase: 'idle', message: '' }, this, "progress");
        this.__launching = new ObservedPropertySimplePU(false, this, "launching");
        this.navStack = null;
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: HomeTab_Params) {
        if (params.versions !== undefined) {
            this.versions = params.versions;
        }
        if (params.progress !== undefined) {
            this.progress = params.progress;
        }
        if (params.launching !== undefined) {
            this.launching = params.launching;
        }
        if (params.navStack !== undefined) {
            this.navStack = params.navStack;
        }
    }
    updateStateVars(params: HomeTab_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__selectedVersion.purgeDependencyOnElmtId(rmElmtId);
        this.__ramMb.purgeDependencyOnElmtId(rmElmtId);
        this.__accountName.purgeDependencyOnElmtId(rmElmtId);
        this.__accountReady.purgeDependencyOnElmtId(rmElmtId);
        this.__selfTestMode.purgeDependencyOnElmtId(rmElmtId);
        this.__versions.purgeDependencyOnElmtId(rmElmtId);
        this.__progress.purgeDependencyOnElmtId(rmElmtId);
        this.__launching.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__selectedVersion.aboutToBeDeleted();
        this.__ramMb.aboutToBeDeleted();
        this.__accountName.aboutToBeDeleted();
        this.__accountReady.aboutToBeDeleted();
        this.__selfTestMode.aboutToBeDeleted();
        this.__versions.aboutToBeDeleted();
        this.__progress.aboutToBeDeleted();
        this.__launching.aboutToBeDeleted();
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
    private __ramMb: ObservedPropertyAbstractPU<number>;
    get ramMb() {
        return this.__ramMb.get();
    }
    set ramMb(newValue: number) {
        this.__ramMb.set(newValue);
    }
    private __accountName: ObservedPropertyAbstractPU<string>;
    get accountName() {
        return this.__accountName.get();
    }
    set accountName(newValue: string) {
        this.__accountName.set(newValue);
    }
    private __accountReady: ObservedPropertyAbstractPU<boolean>;
    get accountReady() {
        return this.__accountReady.get();
    }
    set accountReady(newValue: boolean) {
        this.__accountReady.set(newValue);
    }
    private __selfTestMode: ObservedPropertyAbstractPU<boolean>;
    get selfTestMode() {
        return this.__selfTestMode.get();
    }
    set selfTestMode(newValue: boolean) {
        this.__selfTestMode.set(newValue);
    }
    private __versions: ObservedPropertyObjectPU<Array<VersionEntry>>;
    get versions() {
        return this.__versions.get();
    }
    set versions(newValue: Array<VersionEntry>) {
        this.__versions.set(newValue);
    }
    private __progress: ObservedPropertyObjectPU<LaunchProgress>;
    get progress() {
        return this.__progress.get();
    }
    set progress(newValue: LaunchProgress) {
        this.__progress.set(newValue);
    }
    private __launching: ObservedPropertySimplePU<boolean>;
    get launching() {
        return this.__launching.get();
    }
    set launching(newValue: boolean) {
        this.__launching.set(newValue);
    }
    private navStack: NavPathStack | null;
    aboutToAppear(): void {
        this.ramMb = clampRam(this.ramMb);
        VersionManifestInstance.load().then((entries: Array<VersionEntry>) => {
            this.versions = entries.filter((e: VersionEntry) => e.type === 'release');
            if (this.selectedVersion.length === 0 && this.versions.length > 0) {
                this.selectedVersion = this.versions[0].id;
            }
        });
        GameLauncher.onProgress((p: LaunchProgress) => {
            this.progress = p;
            if (p.phase === 'running') {
                this.launching = false;
            }
            else if (p.phase === 'failed') {
                this.launching = false;
            }
        });
    }
    private async play(): Promise<void> {
        if (this.launching) {
            return;
        }
        this.launching = true;
        // Launch resolves once the JVM thread has been spawned; jump to the game
        // view so the user sees the surface + console immediately.
        const ok: boolean = await GameLauncher.launch(this.selectedVersion);
        if (ok) {
            GameLauncherPushBridge.push();
        }
        else {
            this.launching = false;
        }
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create();
            Scroll.debugLine("entry/src/main/ets/pages/HomeTab.ets(68:5)", "entry");
            Scroll.scrollBar(BarState.Auto);
            Scroll.width('100%');
            Scroll.height('100%');
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            GridRow.create({ columns: { sm: 4, md: 8, lg: 12 }, gutter: 12 });
            GridRow.debugLine("entry/src/main/ets/pages/HomeTab.ets(69:7)", "entry");
            GridRow.width('100%');
            GridRow.padding({ left: 16, right: 16, bottom: 16 });
        }, GridRow);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            GridCol.create({ span: { sm: 4, md: 8, lg: 12 } });
            GridCol.debugLine("entry/src/main/ets/pages/HomeTab.ets(70:7)", "entry");
        }, GridCol);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/HomeTab.ets(71:9)", "entry");
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('MC4HOS');
            Text.debugLine("entry/src/main/ets/pages/HomeTab.ets(72:11)", "entry");
            Text.fontSize(26);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor('#FFFFFF');
            Text.width('100%');
            Text.textAlign(TextAlign.Start);
            Text.margin({ top: 16 });
        }, Text);
        Text.pop();
        Column.pop();
        GridCol.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Account card
            GridCol.create({ span: { sm: 4, md: 4, lg: 4 } });
            GridCol.debugLine("entry/src/main/ets/pages/HomeTab.ets(83:7)", "entry");
        }, GridCol);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/HomeTab.ets(84:9)", "entry");
            Column.width('100%');
            Column.padding(16);
            Column.borderRadius(12);
            Column.backgroundColor('#1F2430');
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.accountReady ? this.accountName : 'Not signed in');
            Text.debugLine("entry/src/main/ets/pages/HomeTab.ets(85:11)", "entry");
            Text.fontSize(18);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor(this.accountReady ? '#63C36A' : '#D35F5F');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.accountReady ? 'Microsoft account' : 'Add an account in the Accounts tab');
            Text.debugLine("entry/src/main/ets/pages/HomeTab.ets(89:11)", "entry");
            Text.fontSize(12);
            Text.fontColor('#8FA0B3');
            Text.margin({ top: 4 });
        }, Text);
        Text.pop();
        Column.pop();
        // Account card
        GridCol.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Version picker
            GridCol.create({ span: { sm: 4, md: 4, lg: 4 } });
            GridCol.debugLine("entry/src/main/ets/pages/HomeTab.ets(102:7)", "entry");
        }, GridCol);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/HomeTab.ets(103:9)", "entry");
            Column.width('100%');
            Column.padding(16);
            Column.borderRadius(12);
            Column.backgroundColor('#1F2430');
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Version');
            Text.debugLine("entry/src/main/ets/pages/HomeTab.ets(104:11)", "entry");
            Text.fontSize(12);
            Text.fontColor('#8FA0B3');
            Text.width('100%');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Select.create(this.versions.map((e: VersionEntry) => {
                const opt: SelectOption = { value: e.id };
                return opt;
            }));
            Select.debugLine("entry/src/main/ets/pages/HomeTab.ets(108:11)", "entry");
            Select.selected(this.selectedVersionIndex());
            Select.value(this.selectedVersion.length > 0 ? this.selectedVersion : 'Select version');
            Select.fontColor('#FFFFFF');
            Select.font({ size: 15 });
            Select.width('100%');
            Select.margin({ top: 6 });
            Select.onSelect((index: number) => {
                if (index >= 0 && index < this.versions.length) {
                    this.selectedVersion = this.versions[index].id;
                }
            });
        }, Select);
        Select.pop();
        Column.pop();
        // Version picker
        GridCol.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // RAM slider
            GridCol.create({ span: { sm: 4, md: 4, lg: 4 } });
            GridCol.debugLine("entry/src/main/ets/pages/HomeTab.ets(132:7)", "entry");
        }, GridCol);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/HomeTab.ets(133:9)", "entry");
            Column.width('100%');
            Column.padding(16);
            Column.borderRadius(12);
            Column.backgroundColor('#1F2430');
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/HomeTab.ets(134:11)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Memory');
            Text.debugLine("entry/src/main/ets/pages/HomeTab.ets(135:13)", "entry");
            Text.fontSize(12);
            Text.fontColor('#8FA0B3');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/HomeTab.ets(138:13)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`${this.ramMb} MB`);
            Text.debugLine("entry/src/main/ets/pages/HomeTab.ets(139:13)", "entry");
            Text.fontSize(12);
            Text.fontColor('#63C36A');
        }, Text);
        Text.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Slider.create({ value: this.ramMb, min: 1024, max: maxDeviceRamMb(), step: 256 });
            Slider.debugLine("entry/src/main/ets/pages/HomeTab.ets(144:11)", "entry");
            Slider.selectedColor('#63C36A');
            Slider.width('100%');
            Slider.margin({ top: 8 });
            Slider.onChange((value: number, mode: SliderChangeMode) => {
                if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                    this.ramMb = clampRam(Math.round(value / 256) * 256);
                }
            });
        }, Slider);
        Column.pop();
        // RAM slider
        GridCol.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Launch progress
            GridCol.create({ span: { sm: 4, md: 8, lg: 12 } });
            GridCol.debugLine("entry/src/main/ets/pages/HomeTab.ets(162:7)", "entry");
        }, GridCol);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/HomeTab.ets(163:9)", "entry");
            Column.width('100%');
            Column.margin({ top: 8 });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.progress.phase !== 'idle' && this.progress.message.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(`${this.progress.phase}: ${this.progress.message}`);
                        Text.debugLine("entry/src/main/ets/pages/HomeTab.ets(165:13)", "entry");
                        Text.fontSize(12);
                        Text.fontColor(this.progress.phase === 'failed' ? '#D35F5F' : '#8FA0B3');
                        Text.width('100%');
                        Text.textAlign(TextAlign.Start);
                        Text.maxLines(2);
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
            Button.createWithLabel(this.selfTestMode ? 'RUN SELF-TEST' : 'PLAY');
            Button.debugLine("entry/src/main/ets/pages/HomeTab.ets(172:11)", "entry");
            Button.width('100%');
            Button.height(48);
            Button.fontSize(17);
            Button.fontWeight(FontWeight.Bold);
            Button.backgroundColor(this.launching ? '#3E5A43' : '#63C36A');
            Button.fontColor('#FFFFFF');
            Button.margin({ top: 8 });
            Button.enabled(!this.launching);
            Button.onClick(() => {
                this.play();
            });
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('Open game view');
            Button.debugLine("entry/src/main/ets/pages/HomeTab.ets(184:11)", "entry");
            Button.width('100%');
            Button.height(36);
            Button.fontSize(13);
            Button.backgroundColor('#2A3340');
            Button.fontColor('#8FA0B3');
            Button.margin({ top: 8 });
            Button.onClick(() => {
                this.pushGameView();
            });
        }, Button);
        Button.pop();
        Column.pop();
        // Launch progress
        GridCol.pop();
        GridRow.pop();
        Scroll.pop();
    }
    private selectedVersionIndex(): number {
        for (let i = 0; i < this.versions.length; i++) {
            if (this.versions[i].id === this.selectedVersion) {
                return i;
            }
        }
        return -1;
    }
    private pushGameView(): void {
        // HomeTab is embedded directly in the Navigation root, so the provided
        // stack is reachable through the global AppStorage bridge set by Index.
        GameLauncherPushBridge.push();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
/**
 * Minimal bridge so embedded tabs can navigate the parent Navigation stack
 * without prop-drilling the NavPathStack through every component.
 */
export class GameLauncherPushBridge {
    private static stack: NavPathStack | null = null;
    public static bind(stack: NavPathStack): void {
        GameLauncherPushBridge.stack = stack;
    }
    public static push(): void {
        if (GameLauncherPushBridge.stack !== null) {
            GameLauncherPushBridge.stack.pushPathByName('game', null);
        }
    }
    public static pushControls(): void {
        if (GameLauncherPushBridge.stack !== null) {
            GameLauncherPushBridge.stack.pushPathByName('controls', null);
        }
    }
    public static pop(): void {
        if (GameLauncherPushBridge.stack !== null) {
            GameLauncherPushBridge.stack.pop();
        }
    }
}
