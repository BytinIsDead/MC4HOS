if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface ControlsEditorPage_Params {
    layout?: ControlLayoutSpec;
    dirty?: boolean;
    savedHint?: string;
}
import { VirtualControls } from "@normalized:N&&&entry/src/main/ets/ui/VirtualControls&";
import { ControlLayoutStore } from "@normalized:N&&&entry/src/main/ets/ui/ControlLayout&";
import type { ControlLayoutSpec } from "@normalized:N&&&entry/src/main/ets/ui/ControlLayout&";
import { GameLauncherPushBridge } from "@normalized:N&&&entry/src/main/ets/pages/HomeTab&";
export class ControlsEditorPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__layout = new ObservedPropertyObjectPU({ layoutVersion: 1, buttons: [], mouseSensitivity: 1.0 }, this, "layout");
        this.__dirty = new ObservedPropertySimplePU(false, this, "dirty");
        this.__savedHint = new ObservedPropertySimplePU('', this, "savedHint");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: ControlsEditorPage_Params) {
        if (params.layout !== undefined) {
            this.layout = params.layout;
        }
        if (params.dirty !== undefined) {
            this.dirty = params.dirty;
        }
        if (params.savedHint !== undefined) {
            this.savedHint = params.savedHint;
        }
    }
    updateStateVars(params: ControlsEditorPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__layout.purgeDependencyOnElmtId(rmElmtId);
        this.__dirty.purgeDependencyOnElmtId(rmElmtId);
        this.__savedHint.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__layout.aboutToBeDeleted();
        this.__dirty.aboutToBeDeleted();
        this.__savedHint.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __layout: ObservedPropertyObjectPU<ControlLayoutSpec>;
    get layout() {
        return this.__layout.get();
    }
    set layout(newValue: ControlLayoutSpec) {
        this.__layout.set(newValue);
    }
    private __dirty: ObservedPropertySimplePU<boolean>;
    get dirty() {
        return this.__dirty.get();
    }
    set dirty(newValue: boolean) {
        this.__dirty.set(newValue);
    }
    private __savedHint: ObservedPropertySimplePU<string>;
    get savedHint() {
        return this.__savedHint.get();
    }
    set savedHint(newValue: string) {
        this.__savedHint.set(newValue);
    }
    aboutToAppear(): void {
        ControlLayoutStore.load().then((layout: ControlLayoutSpec) => {
            this.layout = layout;
        });
    }
    private async save(): Promise<void> {
        await ControlLayoutStore.save(this.layout);
        this.dirty = false;
        this.savedHint = 'Layout saved.';
    }
    private async reset(): Promise<void> {
        this.layout = await ControlLayoutStore.reset();
        this.dirty = true;
        this.savedHint = 'Layout reset to default (not saved yet).';
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Stack.create();
            Stack.debugLine("entry/src/main/ets/pages/ControlsEditorPage.ets(44:5)", "entry");
            Stack.width('100%');
            Stack.height('100%');
            Stack.backgroundColor('#14181F');
        }, Stack);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            __Common__.create();
            __Common__.width('100%');
            __Common__.height('100%');
        }, __Common__);
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new VirtualControls(this, {
                        layout: this.layout,
                        editMode: true
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/ControlsEditorPage.ets", line: 45, col: 7 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            layout: this.layout,
                            editMode: true
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        editMode: true
                    });
                }
            }, { name: "VirtualControls" });
        }
        __Common__.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/ControlsEditorPage.ets(52:7)", "entry");
            Column.width('100%');
            Column.height('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/ControlsEditorPage.ets(53:9)", "entry");
            Row.width('100%');
            Row.padding(8);
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('✕');
            Button.debugLine("entry/src/main/ets/pages/ControlsEditorPage.ets(54:11)", "entry");
            Button.width(36);
            Button.height(36);
            Button.fontSize(16);
            Button.backgroundColor('#2A3340');
            Button.onClick(() => {
                GameLauncherPushBridge.pop();
            });
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/ControlsEditorPage.ets(62:11)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('Reset');
            Button.debugLine("entry/src/main/ets/pages/ControlsEditorPage.ets(63:11)", "entry");
            Button.height(36);
            Button.fontSize(13);
            Button.backgroundColor('#B33A3A');
            Button.onClick(() => {
                this.reset();
            });
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('Save');
            Button.debugLine("entry/src/main/ets/pages/ControlsEditorPage.ets(70:11)", "entry");
            Button.height(36);
            Button.fontSize(13);
            Button.backgroundColor(this.dirty ? '#63C36A' : '#3E5A43');
            Button.margin({ left: 8 });
            Button.onClick(() => {
                this.save();
            });
        }, Button);
        Button.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/ControlsEditorPage.ets(82:9)", "entry");
            Row.width('100%');
            Row.padding({ left: 8, right: 8, top: 4 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Mouse sensitivity');
            Text.debugLine("entry/src/main/ets/pages/ControlsEditorPage.ets(83:11)", "entry");
            Text.fontSize(12);
            Text.fontColor('#8FA0B3');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/ControlsEditorPage.ets(86:11)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`${this.layout.mouseSensitivity.toFixed(1)}×`);
            Text.debugLine("entry/src/main/ets/pages/ControlsEditorPage.ets(87:11)", "entry");
            Text.fontSize(12);
            Text.fontColor('#5FA8D3');
        }, Text);
        Text.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Slider.create({ value: this.layout.mouseSensitivity * 10, min: 3, max: 30, step: 1 });
            Slider.debugLine("entry/src/main/ets/pages/ControlsEditorPage.ets(93:9)", "entry");
            Slider.selectedColor('#5FA8D3');
            Slider.width('100%');
            Slider.padding({ left: 8, right: 8 });
            Slider.onChange((value: number, mode: SliderChangeMode) => {
                this.layout = {
                    layoutVersion: this.layout.layoutVersion,
                    buttons: this.layout.buttons.slice(),
                    mouseSensitivity: Math.round(value) / 10
                };
                this.dirty = true;
            });
        }, Slider);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Drag any element to reposition. Buttons dispatch the key while held.');
            Text.debugLine("entry/src/main/ets/pages/ControlsEditorPage.ets(106:9)", "entry");
            Text.fontSize(11);
            Text.fontColor('#8FA0B3');
            Text.width('100%');
            Text.padding({ left: 8, right: 8, top: 4 });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.savedHint.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.savedHint);
                        Text.debugLine("entry/src/main/ets/pages/ControlsEditorPage.ets(113:11)", "entry");
                        Text.fontSize(11);
                        Text.fontColor('#63C36A');
                        Text.width('100%');
                        Text.padding({ left: 8, top: 4 });
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
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/ControlsEditorPage.ets(120:9)", "entry");
        }, Blank);
        Blank.pop();
        Column.pop();
        Stack.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
