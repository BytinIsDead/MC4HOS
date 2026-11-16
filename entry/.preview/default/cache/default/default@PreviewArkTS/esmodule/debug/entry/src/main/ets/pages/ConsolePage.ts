if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface ConsolePage_Params {
    lines?: Array<LogLine>;
    autoscroll?: boolean;
    scroller?: Scroller;
    listener?: ((event: emitter.EventData) => void) | null;
}
import emitter from "@ohos:events.emitter";
import { ConsoleBuffer, LOG_LEVEL_WARN, LOG_LEVEL_ERROR, CONSOLE_EVENT_ID } from "@normalized:N&&&entry/src/main/ets/common/Logger&";
import type { LogLine } from "@normalized:N&&&entry/src/main/ets/common/Logger&";
import { Paths } from "@normalized:N&&&entry/src/main/ets/common/Paths&";
export class ConsolePage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__lines = new ObservedPropertyObjectPU([], this, "lines");
        this.__autoscroll = new ObservedPropertySimplePU(true, this, "autoscroll");
        this.scroller = new Scroller();
        this.listener = null;
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: ConsolePage_Params) {
        if (params.lines !== undefined) {
            this.lines = params.lines;
        }
        if (params.autoscroll !== undefined) {
            this.autoscroll = params.autoscroll;
        }
        if (params.scroller !== undefined) {
            this.scroller = params.scroller;
        }
        if (params.listener !== undefined) {
            this.listener = params.listener;
        }
    }
    updateStateVars(params: ConsolePage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__lines.purgeDependencyOnElmtId(rmElmtId);
        this.__autoscroll.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__lines.aboutToBeDeleted();
        this.__autoscroll.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __lines: ObservedPropertyObjectPU<Array<LogLine>>;
    get lines() {
        return this.__lines.get();
    }
    set lines(newValue: Array<LogLine>) {
        this.__lines.set(newValue);
    }
    private __autoscroll: ObservedPropertySimplePU<boolean>;
    get autoscroll() {
        return this.__autoscroll.get();
    }
    set autoscroll(newValue: boolean) {
        this.__autoscroll.set(newValue);
    }
    private scroller: Scroller;
    private listener: ((event: emitter.EventData) => void) | null;
    aboutToAppear(): void {
        this.lines = ConsoleBuffer.snapshot();
        this.listener = (event: emitter.EventData) => {
            const data: Record<string, Object> | undefined = event.data;
            if (data === undefined) {
                return;
            }
            const message: string = data['message'] as string;
            if (message === undefined || message.length === 0) {
                return;
            }
            this.lines = ConsoleBuffer.snapshot();
            if (this.autoscroll) {
                this.scroller.scrollEdge(Edge.Bottom);
            }
        };
        const consoleEvent: emitter.InnerEvent = { eventId: CONSOLE_EVENT_ID };
        emitter.on(consoleEvent, this.listener);
    }
    aboutToDisappear(): void {
        if (this.listener !== null) {
            const consoleEvent: emitter.InnerEvent = { eventId: CONSOLE_EVENT_ID };
            emitter.off(consoleEvent, this.listener);
            this.listener = null;
        }
    }
    private colorFor(level: number): string {
        if (level === LOG_LEVEL_ERROR) {
            return '#D35F5F';
        }
        if (level === LOG_LEVEL_WARN) {
            return '#D9A94E';
        }
        return '#9FB6CD';
    }
    private saveLog(): void {
        const path: string = `${Paths.logsDir()}/console-${Date.now()}.log`;
        try {
            Paths.ensureDir(Paths.logsDir());
            Paths.writeTextFileSync(path, this.lines.map((l: LogLine) => `[${new Date(l.timestampMs).toISOString()}] ${l.tag}: ${l.message}`).join('\n'));
            ConsoleBuffer.push({
                level: 1, tag: 'Console', message: `log saved to ${path}`, timestampMs: Date.now()
            });
            this.lines = ConsoleBuffer.snapshot();
        }
        catch (err) {
            // best effort
        }
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/ConsolePage.ets(80:5)", "entry");
            Column.width('100%');
            Column.height('100%');
            Column.onAreaChange((_o: Area, _n: Area) => {
                this.lines = ConsoleBuffer.snapshot();
            });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/ConsolePage.ets(81:7)", "entry");
            Row.width('100%');
            Row.padding({ left: 16, right: 16, top: 12, bottom: 8 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Console');
            Text.debugLine("entry/src/main/ets/pages/ConsolePage.ets(82:9)", "entry");
            Text.fontSize(18);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor('#FFFFFF');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/ConsolePage.ets(86:9)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Toggle.create({ type: ToggleType.Checkbox, isOn: this.autoscroll });
            Toggle.debugLine("entry/src/main/ets/pages/ConsolePage.ets(87:9)", "entry");
            Toggle.onChange((isOn: boolean) => {
                this.autoscroll = isOn;
            });
        }, Toggle);
        Toggle.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('autoscroll');
            Text.debugLine("entry/src/main/ets/pages/ConsolePage.ets(91:9)", "entry");
            Text.fontSize(11);
            Text.fontColor('#8FA0B3');
            Text.margin({ right: 8 });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('Save');
            Button.debugLine("entry/src/main/ets/pages/ConsolePage.ets(95:9)", "entry");
            Button.height(32);
            Button.fontSize(12);
            Button.backgroundColor('#2A3340');
            Button.onClick(() => {
                this.saveLog();
            });
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('Clear');
            Button.debugLine("entry/src/main/ets/pages/ConsolePage.ets(102:9)", "entry");
            Button.height(32);
            Button.fontSize(12);
            Button.backgroundColor('#2A3340');
            Button.margin({ left: 6 });
            Button.onClick(() => {
                ConsoleBuffer.clear();
                this.lines = [];
            });
        }, Button);
        Button.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create(this.scroller);
            Scroll.debugLine("entry/src/main/ets/pages/ConsolePage.ets(115:7)", "entry");
            Scroll.layoutWeight(1);
            Scroll.scrollBar(BarState.Auto);
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/ConsolePage.ets(116:9)", "entry");
            Column.constraintSize({ minWidth: '100%' });
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = (_item, index: number) => {
                const line = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(`${line.tag} › ${line.message}`);
                    Text.debugLine("entry/src/main/ets/pages/ConsolePage.ets(118:13)", "entry");
                    Text.fontSize(11);
                    Text.fontColor(this.colorFor(line.level));
                    Text.fontFamily('monospace');
                    Text.width('100%');
                    Text.padding({ left: 16, right: 16, top: 1, bottom: 1 });
                }, Text);
                Text.pop();
            };
            this.forEachUpdateFunction(elmtId, this.lines, forEachItemGenFunction, (line: LogLine, index: number) => `${index}-${line.timestampMs}`, true, true);
        }, ForEach);
        ForEach.pop();
        Column.pop();
        Scroll.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
