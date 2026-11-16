if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface GamePageView_Params {
    surfaceReady?: boolean;
    controlsVisible?: boolean;
    overlayLayout?: ControlLayoutSpec;
    progress?: LaunchProgress;
    lastLogLines?: Array<string>;
    navStack?: NavPathStack;
    consoleListener?: ((event: emitter.EventData) => void) | null;
}
import window from "@ohos:window";
import { VirtualControls } from "@normalized:N&&&entry/src/main/ets/ui/VirtualControls&";
import { ControlLayoutStore } from "@normalized:N&&&entry/src/main/ets/ui/ControlLayout&";
import type { ControlLayoutSpec } from "@normalized:N&&&entry/src/main/ets/ui/ControlLayout&";
import { GameLauncher } from "@normalized:N&&&entry/src/main/ets/launch/GameLauncher&";
import type { LaunchProgress } from "@normalized:N&&&entry/src/main/ets/launch/GameLauncher&";
import { CONSOLE_EVENT_ID } from "@normalized:N&&&entry/src/main/ets/common/Logger&";
import emitter from "@ohos:events.emitter";
export class GamePageView extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__surfaceReady = new ObservedPropertySimplePU(false, this, "surfaceReady");
        this.__controlsVisible = new ObservedPropertySimplePU(true, this, "controlsVisible");
        this.__overlayLayout = new ObservedPropertyObjectPU({ layoutVersion: 1, buttons: [], mouseSensitivity: 1.0 }, this, "overlayLayout");
        this.__progress = new ObservedPropertyObjectPU({ phase: 'idle', message: '' }, this, "progress");
        this.__lastLogLines = new ObservedPropertyObjectPU([], this, "lastLogLines");
        this.__navStack = this.initializeConsume('nav', "navStack");
        this.consoleListener = null;
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: GamePageView_Params) {
        if (params.surfaceReady !== undefined) {
            this.surfaceReady = params.surfaceReady;
        }
        if (params.controlsVisible !== undefined) {
            this.controlsVisible = params.controlsVisible;
        }
        if (params.overlayLayout !== undefined) {
            this.overlayLayout = params.overlayLayout;
        }
        if (params.progress !== undefined) {
            this.progress = params.progress;
        }
        if (params.lastLogLines !== undefined) {
            this.lastLogLines = params.lastLogLines;
        }
        if (params.consoleListener !== undefined) {
            this.consoleListener = params.consoleListener;
        }
    }
    updateStateVars(params: GamePageView_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__surfaceReady.purgeDependencyOnElmtId(rmElmtId);
        this.__controlsVisible.purgeDependencyOnElmtId(rmElmtId);
        this.__overlayLayout.purgeDependencyOnElmtId(rmElmtId);
        this.__progress.purgeDependencyOnElmtId(rmElmtId);
        this.__lastLogLines.purgeDependencyOnElmtId(rmElmtId);
        this.__navStack.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__surfaceReady.aboutToBeDeleted();
        this.__controlsVisible.aboutToBeDeleted();
        this.__overlayLayout.aboutToBeDeleted();
        this.__progress.aboutToBeDeleted();
        this.__lastLogLines.aboutToBeDeleted();
        this.__navStack.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __surfaceReady: ObservedPropertySimplePU<boolean>;
    get surfaceReady() {
        return this.__surfaceReady.get();
    }
    set surfaceReady(newValue: boolean) {
        this.__surfaceReady.set(newValue);
    }
    private __controlsVisible: ObservedPropertySimplePU<boolean>;
    get controlsVisible() {
        return this.__controlsVisible.get();
    }
    set controlsVisible(newValue: boolean) {
        this.__controlsVisible.set(newValue);
    }
    private __overlayLayout: ObservedPropertyObjectPU<ControlLayoutSpec>;
    get overlayLayout() {
        return this.__overlayLayout.get();
    }
    set overlayLayout(newValue: ControlLayoutSpec) {
        this.__overlayLayout.set(newValue);
    }
    private __progress: ObservedPropertyObjectPU<LaunchProgress>;
    get progress() {
        return this.__progress.get();
    }
    set progress(newValue: LaunchProgress) {
        this.__progress.set(newValue);
    }
    private __lastLogLines: ObservedPropertyObjectPU<Array<string>>;
    get lastLogLines() {
        return this.__lastLogLines.get();
    }
    set lastLogLines(newValue: Array<string>) {
        this.__lastLogLines.set(newValue);
    }
    private __navStack: ObservedPropertyAbstractPU<NavPathStack>;
    get navStack() {
        return this.__navStack.get();
    }
    set navStack(newValue: NavPathStack) {
        this.__navStack.set(newValue);
    }
    private consoleListener: ((event: emitter.EventData) => void) | null;
    aboutToAppear(): void {
        ControlLayoutStore.load().then((layout: ControlLayoutSpec) => {
            this.overlayLayout = layout;
        });
        GameLauncher.onProgress((p: LaunchProgress) => {
            this.progress = p;
        });
        this.consoleListener = (event: emitter.EventData) => {
            const data: Record<string, Object> | undefined = event.data;
            if (data === undefined) {
                return;
            }
            const message: string = data['message'] as string;
            if (message === undefined || message.length === 0) {
                return;
            }
            this.lastLogLines = this.lastLogLines.concat(message).slice(-4);
        };
        const consoleEvent: emitter.InnerEvent = { eventId: CONSOLE_EVENT_ID };
        emitter.on(consoleEvent, this.consoleListener);
        window.getLastWindow(getContext(this)).then((w: window.Window) => {
            w.setPreferredOrientation(window.Orientation.LANDSCAPE);
            w.setWindowLayoutFullScreen(true);
        });
    }
    aboutToDisappear(): void {
        if (this.consoleListener !== null) {
            const consoleEvent: emitter.InnerEvent = { eventId: CONSOLE_EVENT_ID };
            emitter.off(consoleEvent, this.consoleListener);
            this.consoleListener = null;
        }
        window.getLastWindow(getContext(this)).then((w: window.Window) => {
            w.setPreferredOrientation(window.Orientation.PORTRAIT);
            w.setWindowLayoutFullScreen(false);
        });
    }
    private async exitGame(): Promise<void> {
        AlertDialog.show({
            title: 'Leave game?',
            message: 'This terminates the embedded JVM. Unsaved worlds are lost.',
            primaryButton: {
                value: 'Cancel',
                action: () => {
                }
            },
            secondaryButton: {
                value: 'Exit',
                fontColor: '#D35F5F',
                action: () => {
                    GameLauncher.stop().then(() => {
                        this.navStack.pop();
                    });
                }
            }
        });
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Stack.create();
            Stack.debugLine("entry/src/main/ets/pages/GamePage.ets(94:5)", "entry");
            Stack.width('100%');
            Stack.height('100%');
            Stack.backgroundColor('#000000');
        }, Stack);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Native surface: 'library' names the NAPI module that receives the
            // OH_NativeXComponent pointer and EGL window on creation.
            XComponent.create({ id: 'game_surface', type: XComponentType.SURFACE, library: 'mc4hos_core' }, "org.mc4hos.launcher/entry");
            XComponent.debugLine("entry/src/main/ets/pages/GamePage.ets(97:7)", "entry");
            // Native surface: 'library' names the NAPI module that receives the
            // OH_NativeXComponent pointer and EGL window on creation.
            XComponent.width('100%');
            // Native surface: 'library' names the NAPI module that receives the
            // OH_NativeXComponent pointer and EGL window on creation.
            XComponent.height('100%');
            // Native surface: 'library' names the NAPI module that receives the
            // OH_NativeXComponent pointer and EGL window on creation.
            XComponent.onLoad(() => {
                this.surfaceReady = true;
            });
        }, XComponent);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.controlsVisible) {
                this.ifElseBranchUpdateFunction(0, () => {
                    {
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            if (isInitialRender) {
                                let componentCall = new VirtualControls(this, { layout: this.overlayLayout, editMode: false }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/GamePage.ets", line: 105, col: 9 });
                                ViewPU.create(componentCall);
                                let paramsLambda = () => {
                                    return {
                                        layout: this.overlayLayout,
                                        editMode: false
                                    };
                                };
                                componentCall.paramsGenerator_ = paramsLambda;
                            }
                            else {
                                this.updateStateVarsOfChildByElmtId(elmtId, {
                                    editMode: false
                                });
                            }
                        }, { name: "VirtualControls" });
                    }
                });
            }
            // HUD: status + toggles
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // HUD: status + toggles
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/GamePage.ets(109:7)", "entry");
            // HUD: status + toggles
            Column.width('100%');
            // HUD: status + toggles
            Column.height('100%');
            // HUD: status + toggles
            Column.hitTestBehavior(HitTestMode.Transparent);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/GamePage.ets(110:9)", "entry");
            Row.width('100%');
            Row.padding(8);
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('✕');
            Button.debugLine("entry/src/main/ets/pages/GamePage.ets(111:11)", "entry");
            Button.width(36);
            Button.height(36);
            Button.fontSize(16);
            Button.backgroundColor('#B33A3A');
            Button.onClick(() => {
                this.exitGame();
            });
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel(this.controlsVisible ? 'Hide controls' : 'Show controls');
            Button.debugLine("entry/src/main/ets/pages/GamePage.ets(119:11)", "entry");
            Button.height(36);
            Button.fontSize(12);
            Button.backgroundColor('#2A3340');
            Button.margin({ left: 8 });
            Button.onClick(() => {
                this.controlsVisible = !this.controlsVisible;
            });
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/GamePage.ets(127:11)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.progress.phase === 'running' ? (this.surfaceReady ? 'Surface ready' : 'Starting…')
                : `${this.progress.phase} ${this.progress.message}`);
            Text.debugLine("entry/src/main/ets/pages/GamePage.ets(128:11)", "entry");
            Text.fontSize(11);
            Text.fontColor('#8FA0B3');
        }, Text);
        Text.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/GamePage.ets(136:9)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Log ticker
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/GamePage.ets(139:9)", "entry");
            // Log ticker
            Column.width('100%');
            // Log ticker
            Column.padding(6);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const line = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(line);
                    Text.debugLine("entry/src/main/ets/pages/GamePage.ets(141:13)", "entry");
                    Text.fontSize(10);
                    Text.fontColor('#9FB6CD');
                    Text.maxLines(1);
                    Text.width('100%');
                }, Text);
                Text.pop();
            };
            this.forEachUpdateFunction(elmtId, this.lastLogLines, forEachItemGenFunction, (line: string, idx: number) => `${idx}-${line.substring(0, 24)}`, false, true);
        }, ForEach);
        ForEach.pop();
        // Log ticker
        Column.pop();
        // HUD: status + toggles
        Column.pop();
        Stack.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
