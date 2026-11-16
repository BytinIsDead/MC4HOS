if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface SettingsPage_Params {
    ramMb?: number;
    resolutionScale?: number;
    selfTestMode?: boolean;
    clientId?: string;
    savedHint?: string;
}
import preferences from "@ohos:data.preferences";
import type common from "@ohos:app.ability.common";
import { MicrosoftAuth } from "@normalized:N&&&entry/src/main/ets/auth/MicrosoftAuth&";
import { GameLauncherPushBridge } from "@normalized:N&&&entry/src/main/ets/pages/HomeTab&";
import { KEY_RAM_MB, KEY_RESOLUTION_SCALE, KEY_DEMO_MODE, clampRam, maxDeviceRamMb } from "@normalized:N&&&entry/src/main/ets/common/AppState&";
/**
 * Settings: memory, internal render resolution scale, self-test mode,
 * Azure AD client id for the device-code flow, and the control layout
 * editor entry point.
 */
const PREF_NAME: string = 'mc4hos.settings';
const KEY_AZURE_CLIENT_ID: string = 'azureClientId';
export class SettingsPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__ramMb = this.createStorageLink(KEY_RAM_MB, 2048, "ramMb");
        this.__resolutionScale = this.createStorageLink(KEY_RESOLUTION_SCALE, 100, "resolutionScale");
        this.__selfTestMode = this.createStorageLink(KEY_DEMO_MODE, false, "selfTestMode");
        this.__clientId = new ObservedPropertySimplePU('', this, "clientId");
        this.__savedHint = new ObservedPropertySimplePU('', this, "savedHint");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: SettingsPage_Params) {
        if (params.clientId !== undefined) {
            this.clientId = params.clientId;
        }
        if (params.savedHint !== undefined) {
            this.savedHint = params.savedHint;
        }
    }
    updateStateVars(params: SettingsPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__ramMb.purgeDependencyOnElmtId(rmElmtId);
        this.__resolutionScale.purgeDependencyOnElmtId(rmElmtId);
        this.__selfTestMode.purgeDependencyOnElmtId(rmElmtId);
        this.__clientId.purgeDependencyOnElmtId(rmElmtId);
        this.__savedHint.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__ramMb.aboutToBeDeleted();
        this.__resolutionScale.aboutToBeDeleted();
        this.__selfTestMode.aboutToBeDeleted();
        this.__clientId.aboutToBeDeleted();
        this.__savedHint.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __ramMb: ObservedPropertyAbstractPU<number>;
    get ramMb() {
        return this.__ramMb.get();
    }
    set ramMb(newValue: number) {
        this.__ramMb.set(newValue);
    }
    private __resolutionScale: ObservedPropertyAbstractPU<number>;
    get resolutionScale() {
        return this.__resolutionScale.get();
    }
    set resolutionScale(newValue: number) {
        this.__resolutionScale.set(newValue);
    }
    private __selfTestMode: ObservedPropertyAbstractPU<boolean>;
    get selfTestMode() {
        return this.__selfTestMode.get();
    }
    set selfTestMode(newValue: boolean) {
        this.__selfTestMode.set(newValue);
    }
    private __clientId: ObservedPropertySimplePU<string>;
    get clientId() {
        return this.__clientId.get();
    }
    set clientId(newValue: string) {
        this.__clientId.set(newValue);
    }
    private __savedHint: ObservedPropertySimplePU<string>;
    get savedHint() {
        return this.__savedHint.get();
    }
    set savedHint(newValue: string) {
        this.__savedHint.set(newValue);
    }
    aboutToAppear(): void {
        this.loadClientId();
    }
    private async loadClientId(): Promise<void> {
        const context = getContext(this) as common.UIAbilityContext;
        const prefs = await preferences.getPreferences(context, { name: PREF_NAME });
        this.clientId = await prefs.get(KEY_AZURE_CLIENT_ID, '') as string;
    }
    private async saveClientId(): Promise<void> {
        const context = getContext(this) as common.UIAbilityContext;
        const prefs = await preferences.getPreferences(context, { name: PREF_NAME });
        await prefs.put(KEY_AZURE_CLIENT_ID, this.clientId.trim());
        await prefs.flush();
        MicrosoftAuth.configure(this.clientId.trim());
        this.savedHint = this.clientId.trim().length > 0
            ? 'Client id saved.'
            : 'Client id cleared.';
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/SettingsPage.ets(57:5)", "entry");
            Column.width('100%');
            Column.height('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Settings');
            Text.debugLine("entry/src/main/ets/pages/SettingsPage.ets(58:7)", "entry");
            Text.fontSize(18);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor('#FFFFFF');
            Text.width('100%');
            Text.padding({ left: 16, right: 16, top: 12, bottom: 8 });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create();
            Scroll.debugLine("entry/src/main/ets/pages/SettingsPage.ets(65:7)", "entry");
            Scroll.layoutWeight(1);
            Scroll.scrollBar(BarState.Auto);
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/SettingsPage.ets(66:9)", "entry");
            Column.width('100%');
            Column.padding({ left: 16, right: 16, bottom: 24 });
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Memory
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/SettingsPage.ets(68:11)", "entry");
            // Memory
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Memory allocation');
            Text.debugLine("entry/src/main/ets/pages/SettingsPage.ets(69:13)", "entry");
            Text.fontSize(14);
            Text.fontColor('#FFFFFF');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/SettingsPage.ets(72:13)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`${this.ramMb} MB`);
            Text.debugLine("entry/src/main/ets/pages/SettingsPage.ets(73:13)", "entry");
            Text.fontSize(13);
            Text.fontColor('#63C36A');
        }, Text);
        Text.pop();
        // Memory
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Slider.create({ value: this.ramMb, min: 1024, max: maxDeviceRamMb(), step: 256 });
            Slider.debugLine("entry/src/main/ets/pages/SettingsPage.ets(78:11)", "entry");
            Slider.selectedColor('#63C36A');
            Slider.width('100%');
            Slider.onChange((value: number, mode: SliderChangeMode) => {
                if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                    this.ramMb = clampRam(Math.round(value / 256) * 256);
                }
            });
        }, Slider);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Resolution scale
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/SettingsPage.ets(88:11)", "entry");
            // Resolution scale
            Row.width('100%');
            // Resolution scale
            Row.margin({ top: 8 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Internal resolution scale');
            Text.debugLine("entry/src/main/ets/pages/SettingsPage.ets(89:13)", "entry");
            Text.fontSize(14);
            Text.fontColor('#FFFFFF');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/SettingsPage.ets(92:13)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`${this.resolutionScale}%`);
            Text.debugLine("entry/src/main/ets/pages/SettingsPage.ets(93:13)", "entry");
            Text.fontSize(13);
            Text.fontColor('#5FA8D3');
        }, Text);
        Text.pop();
        // Resolution scale
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Slider.create({ value: this.resolutionScale, min: 50, max: 150, step: 10 });
            Slider.debugLine("entry/src/main/ets/pages/SettingsPage.ets(99:11)", "entry");
            Slider.selectedColor('#5FA8D3');
            Slider.width('100%');
            Slider.onChange((value: number, mode: SliderChangeMode) => {
                if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                    this.resolutionScale = Math.round(value / 10) * 10;
                }
            });
        }, Slider);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Self test
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/SettingsPage.ets(109:11)", "entry");
            // Self test
            Row.width('100%');
            // Self test
            Row.margin({ top: 12 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/SettingsPage.ets(110:13)", "entry");
            Column.alignItems(HorizontalAlign.Start);
            Column.layoutWeight(1);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Native self-test mode');
            Text.debugLine("entry/src/main/ets/pages/SettingsPage.ets(111:15)", "entry");
            Text.fontSize(14);
            Text.fontColor('#FFFFFF');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Run the EGL/GLES surface test instead of the game (no account needed).');
            Text.debugLine("entry/src/main/ets/pages/SettingsPage.ets(114:15)", "entry");
            Text.fontSize(11);
            Text.fontColor('#8FA0B3');
            Text.margin({ top: 2 });
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Toggle.create({ type: ToggleType.Switch, isOn: this.selfTestMode });
            Toggle.debugLine("entry/src/main/ets/pages/SettingsPage.ets(121:13)", "entry");
            Toggle.selectedColor('#63C36A');
            Toggle.onChange((isOn: boolean) => {
                this.selfTestMode = isOn;
            });
        }, Toggle);
        Toggle.pop();
        // Self test
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Azure client id
            Text.create('Microsoft OAuth client id');
            Text.debugLine("entry/src/main/ets/pages/SettingsPage.ets(131:11)", "entry");
            // Azure client id
            Text.fontSize(14);
            // Azure client id
            Text.fontColor('#FFFFFF');
            // Azure client id
            Text.width('100%');
            // Azure client id
            Text.margin({ top: 16 });
        }, Text);
        // Azure client id
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Your own Azure AD application (public client, device-code flow enabled). ' +
                'MC4HOS ships no client id. See docs/BUILD.md §7.');
            Text.debugLine("entry/src/main/ets/pages/SettingsPage.ets(136:11)", "entry");
            Text.fontSize(11);
            Text.fontColor('#8FA0B3');
            Text.width('100%');
            Text.margin({ top: 2 });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TextInput.create({ text: this.clientId, placeholder: '00000000-0000-0000-0000-000000000000' });
            TextInput.debugLine("entry/src/main/ets/pages/SettingsPage.ets(142:11)", "entry");
            TextInput.width('100%');
            TextInput.height(40);
            TextInput.fontSize(13);
            TextInput.backgroundColor('#1F2430');
            TextInput.fontColor('#FFFFFF');
            TextInput.margin({ top: 6 });
            TextInput.onChange((value: string) => {
                this.clientId = value;
            });
        }, TextInput);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('Save client id');
            Button.debugLine("entry/src/main/ets/pages/SettingsPage.ets(152:11)", "entry");
            Button.height(34);
            Button.fontSize(12);
            Button.backgroundColor('#2A3340');
            Button.margin({ top: 6 });
            Button.onClick(() => {
                this.saveClientId();
            });
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.savedHint.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.savedHint);
                        Text.debugLine("entry/src/main/ets/pages/SettingsPage.ets(161:13)", "entry");
                        Text.fontSize(11);
                        Text.fontColor('#63C36A');
                        Text.margin({ top: 4 });
                    }, Text);
                    Text.pop();
                });
            }
            // Controls editor
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Controls editor
            Button.createWithLabel('Edit control layout');
            Button.debugLine("entry/src/main/ets/pages/SettingsPage.ets(168:11)", "entry");
            // Controls editor
            Button.width('100%');
            // Controls editor
            Button.height(44);
            // Controls editor
            Button.fontSize(15);
            // Controls editor
            Button.backgroundColor('#5FA8D3');
            // Controls editor
            Button.margin({ top: 20 });
            // Controls editor
            Button.onClick(() => {
                GameLauncherPushBridge.pushControls();
            });
        }, Button);
        // Controls editor
        Button.pop();
        Column.pop();
        Scroll.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
