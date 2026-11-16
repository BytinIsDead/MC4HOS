if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface AccountsPage_Params {
    accountName?: string;
    accountUuid?: string;
    accountXuid?: string;
    accountReady?: boolean;
    authMessage?: string;
    authBusy?: boolean;
    userCode?: string;
    verificationUri?: string;
}
import { MicrosoftAuth } from "@normalized:N&&&entry/src/main/ets/auth/MicrosoftAuth&";
import { AccountStore } from "@normalized:N&&&entry/src/main/ets/auth/AccountStore&";
import type { DeviceCodeResponse, AuthStateUpdate } from '../auth/AuthModels';
import { KEY_ACCOUNT_NAME, KEY_ACCOUNT_UUID, KEY_ACCOUNT_XUID, KEY_ACCOUNT_READY } from "@normalized:N&&&entry/src/main/ets/common/AppState&";
import { Logger } from "@normalized:N&&&entry/src/main/ets/common/Logger&";
export class AccountsPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__accountName = this.createStorageLink(KEY_ACCOUNT_NAME, '', "accountName");
        this.__accountUuid = this.createStorageLink(KEY_ACCOUNT_UUID, '', "accountUuid");
        this.__accountXuid = this.createStorageLink(KEY_ACCOUNT_XUID, '', "accountXuid");
        this.__accountReady = this.createStorageLink(KEY_ACCOUNT_READY, false, "accountReady");
        this.__authMessage = new ObservedPropertySimplePU('', this, "authMessage");
        this.__authBusy = new ObservedPropertySimplePU(false, this, "authBusy");
        this.__userCode = new ObservedPropertySimplePU('', this, "userCode");
        this.__verificationUri = new ObservedPropertySimplePU('', this, "verificationUri");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: AccountsPage_Params) {
        if (params.authMessage !== undefined) {
            this.authMessage = params.authMessage;
        }
        if (params.authBusy !== undefined) {
            this.authBusy = params.authBusy;
        }
        if (params.userCode !== undefined) {
            this.userCode = params.userCode;
        }
        if (params.verificationUri !== undefined) {
            this.verificationUri = params.verificationUri;
        }
    }
    updateStateVars(params: AccountsPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__accountName.purgeDependencyOnElmtId(rmElmtId);
        this.__accountUuid.purgeDependencyOnElmtId(rmElmtId);
        this.__accountXuid.purgeDependencyOnElmtId(rmElmtId);
        this.__accountReady.purgeDependencyOnElmtId(rmElmtId);
        this.__authMessage.purgeDependencyOnElmtId(rmElmtId);
        this.__authBusy.purgeDependencyOnElmtId(rmElmtId);
        this.__userCode.purgeDependencyOnElmtId(rmElmtId);
        this.__verificationUri.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__accountName.aboutToBeDeleted();
        this.__accountUuid.aboutToBeDeleted();
        this.__accountXuid.aboutToBeDeleted();
        this.__accountReady.aboutToBeDeleted();
        this.__authMessage.aboutToBeDeleted();
        this.__authBusy.aboutToBeDeleted();
        this.__userCode.aboutToBeDeleted();
        this.__verificationUri.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __accountName: ObservedPropertyAbstractPU<string>;
    get accountName() {
        return this.__accountName.get();
    }
    set accountName(newValue: string) {
        this.__accountName.set(newValue);
    }
    private __accountUuid: ObservedPropertyAbstractPU<string>;
    get accountUuid() {
        return this.__accountUuid.get();
    }
    set accountUuid(newValue: string) {
        this.__accountUuid.set(newValue);
    }
    private __accountXuid: ObservedPropertyAbstractPU<string>;
    get accountXuid() {
        return this.__accountXuid.get();
    }
    set accountXuid(newValue: string) {
        this.__accountXuid.set(newValue);
    }
    private __accountReady: ObservedPropertyAbstractPU<boolean>;
    get accountReady() {
        return this.__accountReady.get();
    }
    set accountReady(newValue: boolean) {
        this.__accountReady.set(newValue);
    }
    private __authMessage: ObservedPropertySimplePU<string>;
    get authMessage() {
        return this.__authMessage.get();
    }
    set authMessage(newValue: string) {
        this.__authMessage.set(newValue);
    }
    private __authBusy: ObservedPropertySimplePU<boolean>;
    get authBusy() {
        return this.__authBusy.get();
    }
    set authBusy(newValue: boolean) {
        this.__authBusy.set(newValue);
    }
    private __userCode: ObservedPropertySimplePU<string>;
    get userCode() {
        return this.__userCode.get();
    }
    set userCode(newValue: string) {
        this.__userCode.set(newValue);
    }
    private __verificationUri: ObservedPropertySimplePU<string>;
    get verificationUri() {
        return this.__verificationUri.get();
    }
    set verificationUri(newValue: string) {
        this.__verificationUri.set(newValue);
    }
    private async signIn(): Promise<void> {
        if (this.authBusy) {
            return;
        }
        this.authBusy = true;
        this.authMessage = 'Requesting device code…';
        this.userCode = '';
        this.verificationUri = '';
        try {
            const device: DeviceCodeResponse | null = await MicrosoftAuth.beginDeviceFlow();
            if (device === null) {
                this.authMessage = 'Device code request failed. Configure an Azure client id in Settings.';
                this.authBusy = false;
                return;
            }
            this.userCode = device.userCode;
            this.verificationUri = device.verificationUri;
            const result = await MicrosoftAuth.pollAndAuthorize(device, (update: AuthStateUpdate) => {
                this.authMessage = update.message;
            });
            if (result === null) {
                this.authMessage = 'Sign-in did not complete.';
                this.authBusy = false;
                return;
            }
            await AccountStore.saveActiveAccount(result.profile, result.secrets);
            this.accountName = result.profile.displayName;
            this.accountUuid = result.profile.uuid;
            this.accountXuid = result.profile.xuid;
            this.accountReady = true;
            this.authMessage = `Signed in as ${result.profile.displayName}`;
        }
        catch (err) {
            const e = err as Error;
            Logger.error('AccountsPage', `sign-in error: ${e.message}`);
            this.authMessage = `Sign-in error: ${e.message}`;
        }
        this.authBusy = false;
    }
    private async signOut(): Promise<void> {
        await AccountStore.signOut();
        this.accountName = '';
        this.accountUuid = '';
        this.accountXuid = '';
        this.accountReady = false;
        this.authMessage = 'Signed out.';
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/AccountsPage.ets(84:5)", "entry");
            Column.width('100%');
            Column.height('100%');
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Accounts');
            Text.debugLine("entry/src/main/ets/pages/AccountsPage.ets(85:7)", "entry");
            Text.fontSize(18);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor('#FFFFFF');
            Text.width('100%');
            Text.padding({ left: 16, right: 16, top: 12, bottom: 8 });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/AccountsPage.ets(92:7)", "entry");
            Column.width('100%');
            Column.padding(16);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.accountReady ? this.accountName : 'No account');
            Text.debugLine("entry/src/main/ets/pages/AccountsPage.ets(93:9)", "entry");
            Text.fontSize(20);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor(this.accountReady ? '#63C36A' : '#8FA0B3');
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.accountReady) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(`uuid: ${this.accountUuid}`);
                        Text.debugLine("entry/src/main/ets/pages/AccountsPage.ets(98:11)", "entry");
                        Text.fontSize(11);
                        Text.fontColor('#8FA0B3');
                        Text.margin({ top: 4 });
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(`xuid: ${this.accountXuid}`);
                        Text.debugLine("entry/src/main/ets/pages/AccountsPage.ets(102:11)", "entry");
                        Text.fontSize(11);
                        Text.fontColor('#8FA0B3');
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
            if (!this.accountReady) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Button.createWithLabel('Sign in with Microsoft');
                        Button.debugLine("entry/src/main/ets/pages/AccountsPage.ets(107:11)", "entry");
                        Button.width('100%');
                        Button.height(44);
                        Button.fontSize(15);
                        Button.backgroundColor('#5FA8D3');
                        Button.margin({ top: 12 });
                        Button.enabled(!this.authBusy);
                        Button.onClick(() => {
                            this.signIn();
                        });
                    }, Button);
                    Button.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Button.createWithLabel('Sign out');
                        Button.debugLine("entry/src/main/ets/pages/AccountsPage.ets(118:11)", "entry");
                        Button.width('100%');
                        Button.height(44);
                        Button.fontSize(15);
                        Button.backgroundColor('#B33A3A');
                        Button.margin({ top: 12 });
                        Button.onClick(() => {
                            this.signOut();
                        });
                    }, Button);
                    Button.pop();
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.verificationUri.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create();
                        Column.debugLine("entry/src/main/ets/pages/AccountsPage.ets(130:11)", "entry");
                        Column.width('100%');
                        Column.padding(12);
                        Column.borderRadius(8);
                        Column.backgroundColor('#14181F');
                        Column.margin({ top: 12 });
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('On any browser, open:');
                        Text.debugLine("entry/src/main/ets/pages/AccountsPage.ets(131:13)", "entry");
                        Text.fontSize(12);
                        Text.fontColor('#8FA0B3');
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.verificationUri);
                        Text.debugLine("entry/src/main/ets/pages/AccountsPage.ets(134:13)", "entry");
                        Text.fontSize(14);
                        Text.fontWeight(FontWeight.Bold);
                        Text.fontColor('#5FA8D3');
                        Text.margin({ top: 4 });
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('Then enter the code:');
                        Text.debugLine("entry/src/main/ets/pages/AccountsPage.ets(139:13)", "entry");
                        Text.fontSize(12);
                        Text.fontColor('#8FA0B3');
                        Text.margin({ top: 8 });
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.userCode);
                        Text.debugLine("entry/src/main/ets/pages/AccountsPage.ets(143:13)", "entry");
                        Text.fontSize(24);
                        Text.fontWeight(FontWeight.Bold);
                        Text.fontColor('#FFFFFF');
                        Text.letterSpacing(3);
                        Text.margin({ top: 4 });
                    }, Text);
                    Text.pop();
                    Column.pop();
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
            if (this.authMessage.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.authMessage);
                        Text.debugLine("entry/src/main/ets/pages/AccountsPage.ets(158:11)", "entry");
                        Text.fontSize(12);
                        Text.fontColor('#D9A94E');
                        Text.margin({ top: 8 });
                        Text.width('100%');
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
        Column.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
