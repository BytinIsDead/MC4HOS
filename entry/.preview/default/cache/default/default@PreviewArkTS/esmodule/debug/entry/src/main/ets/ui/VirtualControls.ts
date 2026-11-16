if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface VirtualControls_Params {
    layout?: ControlLayoutSpec;
    editMode?: boolean;
    onLayoutEdited?: ((layout: ControlLayoutSpec) => void) | null;
    lastX?: number;
    lastY?: number;
    downX?: number;
    downY?: number;
    downTimeMs?: number;
    movedDistance?: number;
    secondPointerSeen?: boolean;
    dragStart?: Map<string, DragPos>;
    canvasWidth?: number;
    canvasHeight?: number;
}
import { sendKeyEvent, sendMouseButton, sendMouseMove, sendTouchEvent } from "@normalized:\0hvigor_ignore_C:_Users_Bytin_Desktop_MC4HOS_entry_src_main_cpp_types_mc4hos_core_index.d.ts";
import { GlfwKeys, GlfwMouse } from "@normalized:N&&&entry/src/main/ets/ui/ControlLayout&";
import type { ControlButtonSpec, ControlLayoutSpec } from "@normalized:N&&&entry/src/main/ets/ui/ControlLayout&";
/**
 * Custom on-screen input overlay: a mouse touchpad (drag = look, tap = click,
 * two-finger tap = right click), a directional pad, and configurable key
 * buttons. Every interaction is forwarded to the native input bridge, which
 * routes it into the game process through the Java-side InputBridge.
 *
 * Raw touch action codes follow the OHOS convention: 0 down, 1 up, 2 move,
 * 3 cancel.
 */
const ACTION_DOWN: number = 0;
const ACTION_UP: number = 1;
const ACTION_MOVE: number = 2;
const ACTION_CANCEL: number = 3;
const RAW_TOUCH_ID: number = -7; // virtual overlay pointer id space
/** Drag-edit position, in percent of the overlay canvas. */
interface DragPos {
    x: number;
    y: number;
}
export class VirtualControls extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__layout = new ObservedPropertyObjectPU({ layoutVersion: 1, buttons: [], mouseSensitivity: 1.0 }, this, "layout");
        this.__editMode = new SynchedPropertySimpleOneWayPU(params.editMode, this, "editMode");
        this.onLayoutEdited = null;
        this.lastX = -1;
        this.lastY = -1;
        this.downX = 0;
        this.downY = 0;
        this.downTimeMs = 0;
        this.movedDistance = 0;
        this.secondPointerSeen = false;
        this.dragStart = new Map();
        this.__canvasWidth = new ObservedPropertySimplePU(1, this, "canvasWidth");
        this.__canvasHeight = new ObservedPropertySimplePU(1, this, "canvasHeight");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: VirtualControls_Params) {
        if (params.layout !== undefined) {
            this.layout = params.layout;
        }
        if (params.editMode === undefined) {
            this.__editMode.set(false);
        }
        if (params.onLayoutEdited !== undefined) {
            this.onLayoutEdited = params.onLayoutEdited;
        }
        if (params.lastX !== undefined) {
            this.lastX = params.lastX;
        }
        if (params.lastY !== undefined) {
            this.lastY = params.lastY;
        }
        if (params.downX !== undefined) {
            this.downX = params.downX;
        }
        if (params.downY !== undefined) {
            this.downY = params.downY;
        }
        if (params.downTimeMs !== undefined) {
            this.downTimeMs = params.downTimeMs;
        }
        if (params.movedDistance !== undefined) {
            this.movedDistance = params.movedDistance;
        }
        if (params.secondPointerSeen !== undefined) {
            this.secondPointerSeen = params.secondPointerSeen;
        }
        if (params.dragStart !== undefined) {
            this.dragStart = params.dragStart;
        }
        if (params.canvasWidth !== undefined) {
            this.canvasWidth = params.canvasWidth;
        }
        if (params.canvasHeight !== undefined) {
            this.canvasHeight = params.canvasHeight;
        }
    }
    updateStateVars(params: VirtualControls_Params) {
        this.__editMode.reset(params.editMode);
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__layout.purgeDependencyOnElmtId(rmElmtId);
        this.__editMode.purgeDependencyOnElmtId(rmElmtId);
        this.__canvasWidth.purgeDependencyOnElmtId(rmElmtId);
        this.__canvasHeight.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__layout.aboutToBeDeleted();
        this.__editMode.aboutToBeDeleted();
        this.__canvasWidth.aboutToBeDeleted();
        this.__canvasHeight.aboutToBeDeleted();
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
    private __editMode: SynchedPropertySimpleOneWayPU<boolean>;
    get editMode() {
        return this.__editMode.get();
    }
    set editMode(newValue: boolean) {
        this.__editMode.set(newValue);
    }
    /** Invoked after drag-editing moves an element (editor saves via store). */
    private onLayoutEdited: ((layout: ControlLayoutSpec) => void) | null;
    // touchpad state
    private lastX: number;
    private lastY: number;
    private downX: number;
    private downY: number;
    private downTimeMs: number;
    private movedDistance: number;
    private secondPointerSeen: boolean;
    public setOnLayoutEdited(callback: (layout: ControlLayoutSpec) => void): void {
        this.onLayoutEdited = callback;
    }
    public async loadLayout(layout: ControlLayoutSpec): Promise<void> {
        this.layout = layout;
    }
    // ---------------------------------------------------------------------
    // dispatch helpers
    // ---------------------------------------------------------------------
    private pressKeys(keys: Array<number>): void {
        for (const key of keys) {
            sendKeyEvent(key, 0);
        }
    }
    private releaseKeys(keys: Array<number>): void {
        for (const key of keys) {
            sendKeyEvent(key, 1);
        }
    }
    private forwardRawTouch(action: number, x: number, y: number): void {
        sendTouchEvent(RAW_TOUCH_ID, x, y, action);
    }
    private handleTouchpadTouch(event: TouchEvent): void {
        if (this.editMode) {
            return;
        }
        if (event.type === TouchType.Down) {
            this.lastX = event.touches[0].x;
            this.lastY = event.touches[0].y;
            this.downX = this.lastX;
            this.downY = this.lastY;
            this.downTimeMs = Date.now();
            this.movedDistance = 0;
            this.secondPointerSeen = event.touches.length > 1;
            this.forwardRawTouch(ACTION_DOWN, this.lastX, this.lastY);
            return;
        }
        if (event.type === TouchType.Move) {
            if (event.touches.length > 1) {
                this.secondPointerSeen = true;
            }
            if (this.lastX < 0) {
                return;
            }
            const nx: number = event.touches[0].x;
            const ny: number = event.touches[0].y;
            const dx: number = nx - this.lastX;
            const dy: number = ny - this.lastY;
            this.lastX = nx;
            this.lastY = ny;
            this.movedDistance += Math.abs(dx) + Math.abs(dy);
            sendMouseMove(dx * this.layout.mouseSensitivity, dy * this.layout.mouseSensitivity);
            this.forwardRawTouch(ACTION_MOVE, nx, ny);
            return;
        }
        if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            const heldMs: number = Date.now() - this.downTimeMs;
            const isTap: boolean = this.movedDistance < 16 && heldMs < 250;
            this.forwardRawTouch(event.type === TouchType.Up ? ACTION_UP : ACTION_CANCEL, this.lastX < 0 ? 0 : this.lastX, this.lastY < 0 ? 0 : this.lastY);
            this.lastX = -1;
            this.lastY = -1;
            if (isTap && !this.secondPointerSeen) {
                // quick tap = left click (press + release)
                sendMouseButton(GlfwMouse.LEFT, 0);
                sendMouseButton(GlfwMouse.LEFT, 1);
            }
            else if (this.secondPointerSeen) {
                // two-finger tap/release = right click
                sendMouseButton(GlfwMouse.RIGHT, 0);
                sendMouseButton(GlfwMouse.RIGHT, 1);
            }
            this.secondPointerSeen = false;
        }
    }
    // ---------------------------------------------------------------------
    // builders
    // ---------------------------------------------------------------------
    private KeyButton(spec: ControlButtonSpec, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/ui/VirtualControls.ets(140:5)", "entry");
            Column.justifyContent(FlexAlign.Center);
            Column.width(spec.sizeVp);
            Column.height(spec.sizeVp);
            Column.borderRadius(spec.sizeVp / 2);
            Column.backgroundColor(spec.accentColor);
            Column.opacity(this.editMode ? 0.85 : 0.55);
            Column.position({ x: `${spec.xPercent}%`, y: `${spec.yPercent}%` });
            Column.markAnchor({ x: spec.sizeVp / 2, y: spec.sizeVp / 2 });
            Column.onTouch((event: TouchEvent) => {
                if (this.editMode) {
                    return;
                }
                if (event.type === TouchType.Down) {
                    this.pressKeys(spec.keyCodes);
                }
                else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    this.releaseKeys(spec.keyCodes);
                }
            });
            globalThis.Gesture.create(GesturePriority.Low);
            globalThis.Gesture.pop();
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(spec.label);
            Text.debugLine("entry/src/main/ets/ui/VirtualControls.ets(141:7)", "entry");
            Text.fontSize(spec.sizeVp * 0.22);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor('#FFFFFF');
            Text.maxLines(1);
        }, Text);
        Text.pop();
        Column.pop();
    }
    private MouseButton(spec: ControlButtonSpec, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/ui/VirtualControls.ets(180:5)", "entry");
            Column.justifyContent(FlexAlign.Center);
            Column.width(spec.sizeVp);
            Column.height(spec.sizeVp);
            Column.borderRadius(spec.sizeVp / 2);
            Column.backgroundColor(spec.accentColor);
            Column.opacity(this.editMode ? 0.85 : 0.6);
            Column.position({ x: `${spec.xPercent}%`, y: `${spec.yPercent}%` });
            Column.markAnchor({ x: spec.sizeVp / 2, y: spec.sizeVp / 2 });
            Column.onTouch((event: TouchEvent) => {
                if (this.editMode) {
                    return;
                }
                if (event.type === TouchType.Down) {
                    sendMouseButton(spec.mouseButton, 0);
                }
                else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    sendMouseButton(spec.mouseButton, 1);
                }
            });
            globalThis.Gesture.create(GesturePriority.Low);
            globalThis.Gesture.pop();
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(spec.label);
            Text.debugLine("entry/src/main/ets/ui/VirtualControls.ets(181:7)", "entry");
            Text.fontSize(spec.sizeVp * 0.24);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor('#FFFFFF');
        }, Text);
        Text.pop();
        Column.pop();
    }
    private DPad(spec: ControlButtonSpec, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Stack.create();
            Stack.debugLine("entry/src/main/ets/ui/VirtualControls.ets(219:5)", "entry");
            Stack.width(spec.sizeVp);
            Stack.height(spec.sizeVp);
            Stack.position({ x: `${spec.xPercent}%`, y: `${spec.yPercent}%` });
            Stack.markAnchor({ x: spec.sizeVp / 2, y: spec.sizeVp / 2 });
            globalThis.Gesture.create(GesturePriority.Low);
            globalThis.Gesture.pop();
        }, Stack);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/ui/VirtualControls.ets(220:7)", "entry");
            Column.width(spec.sizeVp);
            Column.height(spec.sizeVp);
            Column.borderRadius(spec.sizeVp / 2);
            Column.backgroundColor('#00000000');
            Column.border({ width: 2, color: '#409FB6CD' });
        }, Column);
        Column.pop();
        this.DPadNode.bind(this)(spec, '▲', 0, -1, GlfwKeys.W);
        this.DPadNode.bind(this)(spec, '◀', -1, 0, GlfwKeys.A);
        this.DPadNode.bind(this)(spec, '▼', 0, 1, GlfwKeys.S);
        this.DPadNode.bind(this)(spec, '▶', 1, 0, GlfwKeys.D);
        Stack.pop();
    }
    private DPadNode(spec: ControlButtonSpec, arrow: string, dx: number, dy: number, keyCode: number, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(arrow);
            Text.debugLine("entry/src/main/ets/ui/VirtualControls.ets(250:5)", "entry");
            Text.fontSize(spec.sizeVp * 0.18);
            Text.fontColor('#EAF2F8');
            Text.textAlign(TextAlign.Center);
            Text.width(spec.sizeVp * 0.36);
            Text.height(spec.sizeVp * 0.36);
            Text.borderRadius(spec.sizeVp * 0.18);
            Text.backgroundColor('#669FB6CD');
            Text.offset({ x: dx * spec.sizeVp * 0.28, y: dy * spec.sizeVp * 0.28 });
            Text.onTouch((event: TouchEvent) => {
                if (this.editMode) {
                    return;
                }
                if (event.type === TouchType.Down) {
                    sendKeyEvent(keyCode, 0);
                }
                else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    sendKeyEvent(keyCode, 1);
                }
            });
        }, Text);
        Text.pop();
    }
    private dragElement(spec: ControlButtonSpec, event: GestureEvent): void {
        // GestureEvent offsets are deltas; convert to percent using the canvas
        // size captured at drag start (approximated via component width).
        const dxPercent: number = event.offsetX / this.canvasWidth * 100;
        const dyPercent: number = event.offsetY / this.canvasHeight * 100;
        const base = this.dragBase(spec.id);
        spec.xPercent = clampPercent(base.x + dxPercent);
        spec.yPercent = clampPercent(base.y + dyPercent);
        this.layout = {
            layoutVersion: this.layout.layoutVersion,
            buttons: this.layout.buttons.slice(),
            mouseSensitivity: this.layout.mouseSensitivity
        };
        if (this.onLayoutEdited !== null) {
            this.onLayoutEdited(this.layout);
        }
    }
    /** Drag-edit position bookkeeping. Gesture classes cannot be used as
     * ArkTS return types, so the pan chains are written inline per builder. */
    private dragStart: Map<string, DragPos>;
    private __canvasWidth: ObservedPropertySimplePU<number>;
    get canvasWidth() {
        return this.__canvasWidth.get();
    }
    set canvasWidth(newValue: number) {
        this.__canvasWidth.set(newValue);
    }
    private __canvasHeight: ObservedPropertySimplePU<number>;
    get canvasHeight() {
        return this.__canvasHeight.get();
    }
    set canvasHeight(newValue: number) {
        this.__canvasHeight.set(newValue);
    }
    private dragBase(id: string): DragPos {
        const known = this.dragStart.get(id);
        if (known !== undefined) {
            return known;
        }
        const spec: ControlButtonSpec | undefined = this.layout.buttons.find((b: ControlButtonSpec) => b.id === id);
        const pos: DragPos = {
            x: spec !== undefined ? spec.xPercent : 50,
            y: spec !== undefined ? spec.yPercent : 50
        };
        this.dragStart.set(id, pos);
        return pos;
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Stack.create();
            Stack.debugLine("entry/src/main/ets/ui/VirtualControls.ets(311:5)", "entry");
            Stack.width('100%');
            Stack.height('100%');
            Stack.onAreaChange((_old: Area, newArea: Area) => {
                this.canvasWidth = newArea.width as number;
                this.canvasHeight = newArea.height as number;
            });
        }, Stack);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // Full-area mouse touchpad (also the drag-edit canvas).
            Column.create();
            Column.debugLine("entry/src/main/ets/ui/VirtualControls.ets(313:7)", "entry");
            // Full-area mouse touchpad (also the drag-edit canvas).
            Column.width('100%');
            // Full-area mouse touchpad (also the drag-edit canvas).
            Column.height('100%');
            // Full-area mouse touchpad (also the drag-edit canvas).
            Column.hitTestBehavior(this.editMode ? HitTestMode.Transparent : HitTestMode.Default);
            // Full-area mouse touchpad (also the drag-edit canvas).
            Column.onAreaChange((_old: Area, newArea: Area) => {
                this.canvasWidth = newArea.width as number;
                this.canvasHeight = newArea.height as number;
            });
            // Full-area mouse touchpad (also the drag-edit canvas).
            Column.onTouch((event: TouchEvent) => this.handleTouchpadTouch(event));
        }, Column);
        // Full-area mouse touchpad (also the drag-edit canvas).
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const spec = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    If.create();
                    if (spec.kind === 'dpad') {
                        this.ifElseBranchUpdateFunction(0, () => {
                            this.DPad.bind(this)(spec);
                        });
                    }
                    else if (spec.kind === 'mouse_button') {
                        this.ifElseBranchUpdateFunction(1, () => {
                            this.MouseButton.bind(this)(spec);
                        });
                    }
                    else {
                        this.ifElseBranchUpdateFunction(2, () => {
                            this.KeyButton.bind(this)(spec);
                        });
                    }
                }, If);
                If.pop();
            };
            this.forEachUpdateFunction(elmtId, this.layout.buttons, forEachItemGenFunction, (spec: ControlButtonSpec) => spec.id, false, false);
        }, ForEach);
        ForEach.pop();
        Stack.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
function clampPercent(value: number): number {
    return Math.min(98, Math.max(2, value));
}
