/*
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#include "jvm_loader.h"
#include "jni_bridge.h"
#include "input_bridge.h"
#include "game_surface.h"
#include "log_capture.h"

#include <ace/xcomponent/native_interface_xcomponent.h>
#include <hilog/log.h>
#include <napi/native_api.h>
#include <atomic>
#include <cstring>
#include <string>
#include <vector>

/**
 * NAPI module `mc4hos_core`:
 *
 *  - receives the OH_NativeXComponent instance attached by the ArkUI runtime
 *    (property __NATIVE_XCOMPONENT_OBJ__ on exports) and registers surface /
 *    touch callbacks;
 *  - exposes the launcher API consumed from ArkTS (see index.d.ts).
 */

namespace {

constexpr uint32_t HILOG_DOMAIN = 0x4D43;

napi_threadsafe_function g_logTsfn = nullptr;
std::atomic<bool> g_logInstalled{false};

// ---------------------------------------------------------------------------
// ArkTS -> native plumbing helpers
// ---------------------------------------------------------------------------

bool GetStringProperty(napi_env env, napi_value obj, const char *key, std::string &out) {
    napi_value value = nullptr;
    if (napi_get_named_property(env, obj, key, &value) != napi_ok) {
        return false;
    }
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, value, &type) != napi_ok || type != napi_string) {
        return false;
    }
    size_t size = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &size);
    out.resize(size);
    if (size > 0) {
        napi_get_value_string_utf8(env, value, out.data(), size + 1, &size);
    }
    return true;
}

bool GetStringArrayProperty(napi_env env, napi_value obj, const char *key,
                            std::vector<std::string> &out) {
    napi_value array = nullptr;
    if (napi_get_named_property(env, obj, key, &array) != napi_ok) {
        return false;
    }
    bool isArray = false;
    if (napi_is_array(env, array, &isArray) != napi_ok || !isArray) {
        return false;
    }
    uint32_t length = 0;
    napi_get_array_length(env, array, &length);
    out.reserve(length);
    for (uint32_t i = 0; i < length; i++) {
        napi_value element = nullptr;
        if (napi_get_element(env, array, i, &element) != napi_ok) {
            continue;
        }
        size_t size = 0;
        napi_get_value_string_utf8(env, element, nullptr, 0, &size);
        std::string text;
        text.resize(size);
        if (size > 0) {
            napi_get_value_string_utf8(env, element, text.data(), size + 1, &size);
        }
        out.push_back(text);
    }
    return true;
}

bool GetBoolProperty(napi_env env, napi_value obj, const char *key, bool def) {
    napi_value value = nullptr;
    if (napi_get_named_property(env, obj, key, &value) != napi_ok) {
        return def;
    }
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, value, &type) != napi_ok || type != napi_boolean) {
        return def;
    }
    bool result = def;
    napi_get_value_bool(env, value, &result);
    return result;
}

napi_value BoolValue(napi_env env, bool value) {
    napi_value result = nullptr;
    napi_get_boolean(env, value, &result);
    return result;
}

// ---------------------------------------------------------------------------
// log pump: native lines -> ArkTS callback (thread-safe function)
// ---------------------------------------------------------------------------

void LogCallJs(napi_env env, napi_value jsCallback, void * /*context*/, void *data) {
    std::string *line = static_cast<std::string *>(data);
    if (jsCallback != nullptr && line != nullptr) {
        napi_value undefined = nullptr;
        napi_get_undefined(env, &undefined);
        napi_value arg = nullptr;
        napi_create_string_utf8(env, line->c_str(), line->size(), &arg);
        napi_call_function(env, undefined, jsCallback, 1, &arg, nullptr);
    }
    delete line;
}

void RouteLogLine(const char *line) {
    if (g_logTsfn == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_INFO, HILOG_DOMAIN, "Game", "%{public}s", line);
        return;
    }
    napi_call_threadsafe_function(g_logTsfn, new std::string(line), napi_tsfn_nonblocking);
}

// ---------------------------------------------------------------------------
// exported functions
// ---------------------------------------------------------------------------

napi_value JsInitialize(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc >= 1 && g_logTsfn == nullptr) {
        napi_value resourceName = nullptr;
        napi_create_string_utf8(env, "mc4hosLogPump", NAPI_AUTO_LENGTH, &resourceName);
        napi_create_threadsafe_function(env, argv[0], nullptr, resourceName, 1024, 1,
                                        nullptr, nullptr, nullptr, LogCallJs, &g_logTsfn);
        napi_acquire_threadsafe_function(g_logTsfn);
    }
    if (!g_logInstalled.exchange(true)) {
        mc4hos::log::Install("", RouteLogLine);
    }
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value JsStartGame(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 1) {
        napi_throw_type_error(env, nullptr, "startGame requires a config object");
        return nullptr;
    }

    mc4hos::jvm::LaunchConfig config;
    GetStringProperty(env, argv[0], "javaHome", config.javaHome);
    GetStringProperty(env, argv[0], "classPath", config.classPath);
    GetStringProperty(env, argv[0], "nativesDirs", config.nativesDirs);
    GetStringArrayProperty(env, argv[0], "jvmOptions", config.jvmOptions);
    GetStringProperty(env, argv[0], "mainClass", config.mainClass);
    GetStringArrayProperty(env, argv[0], "gameArgs", config.gameArgs);
    GetStringProperty(env, argv[0], "workingDir", config.workingDir);
    GetStringProperty(env, argv[0], "logDir", config.logDir);
    config.selfTest = GetBoolProperty(env, argv[0], "selfTest", false);

    // Ensure log capture targets the configured directory (re-install is a
    // no-op after the first call).
    mc4hos::log::Install(config.logDir, RouteLogLine);

    napi_value result = nullptr;
    if (config.selfTest) {
        mc4hos::surface::StartSelfTest();
        napi_create_int32(env, 0, &result);
        return result;
    }
    if (config.javaHome.empty() || config.classPath.empty() || config.mainClass.empty()) {
        napi_create_int32(env, mc4hos::jvm::kErrNoJavaHome, &result);
        return result;
    }
    int status = mc4hos::jvm::StartJvm(config);
    napi_create_int32(env, status, &result);
    return result;
}

napi_value JsStopGame(napi_env env, napi_callback_info /*info*/) {
    mc4hos::surface::StopSelfTest();
    mc4hos::jvm::RequestJvmExit();
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value JsIsGameRunning(napi_env env, napi_callback_info /*info*/) {
    return BoolValue(env, mc4hos::jvm::IsJvmRunning());
}

napi_value JsSendKeyEvent(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t code = 0;
    int32_t action = 0;
    if (argc >= 2) {
        napi_get_value_int32(env, argv[0], &code);
        napi_get_value_int32(env, argv[1], &action);
        mc4hos::input::PostKey(code, action);
    }
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value JsSendMouseButton(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t button = 0;
    int32_t action = 0;
    if (argc >= 2) {
        napi_get_value_int32(env, argv[0], &button);
        napi_get_value_int32(env, argv[1], &action);
        mc4hos::input::PostMouseButton(button, action);
    }
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value JsSendMouseMove(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    double dx = 0;
    double dy = 0;
    if (argc >= 2) {
        napi_get_value_double(env, argv[0], &dx);
        napi_get_value_double(env, argv[1], &dy);
        mc4hos::input::PostMouseMove(static_cast<float>(dx), static_cast<float>(dy));
    }
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value JsSendTouchEvent(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value argv[4] = {nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t id = 0;
    int32_t action = 0;
    double x = 0;
    double y = 0;
    if (argc >= 4) {
        napi_get_value_int32(env, argv[0], &id);
        napi_get_value_double(env, argv[1], &x);
        napi_get_value_double(env, argv[2], &y);
        napi_get_value_int32(env, argv[3], &action);
        mc4hos::input::PostTouch(id, static_cast<float>(x), static_cast<float>(y), action);
    }
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

// ---------------------------------------------------------------------------
// XComponent registration
// ---------------------------------------------------------------------------

OH_NativeXComponent_Callback g_xcomponentCallback = {
    .OnSurfaceCreated = [](OH_NativeXComponent *component, void *window) {
        mc4hos::surface::OnSurfaceCreated(component, window);
    },
    .OnSurfaceChanged = [](OH_NativeXComponent *component, void *window) {
        mc4hos::surface::OnSurfaceChanged(component, window);
    },
    .OnSurfaceDestroyed = [](OH_NativeXComponent *component, void *window) {
        mc4hos::surface::OnSurfaceDestroyed(component, window);
    },
    .DispatchTouchEvent = [](OH_NativeXComponent *component, void *window) {
        mc4hos::surface::DispatchTouchEvent(component, window);
    }
};

void AttachXComponent(napi_env env, napi_value exports) {
    napi_value exportInstance = nullptr;
    if (napi_get_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ, &exportInstance) != napi_ok ||
        exportInstance == nullptr) {
        return;
    }
    OH_NativeXComponent *nativeXComponent = nullptr;
    if (napi_unwrap(env, exportInstance, reinterpret_cast<void **>(&nativeXComponent)) != napi_ok ||
        nativeXComponent == nullptr) {
        return;
    }
    OH_NativeXComponent_RegisterCallback(nativeXComponent, &g_xcomponentCallback);
    OH_LOG_Print(LOG_APP, LOG_INFO, HILOG_DOMAIN, "MC4HOS", "XComponent callbacks registered");
}

// ---------------------------------------------------------------------------
// module definition
// ---------------------------------------------------------------------------

napi_value ModuleInit(napi_env env, napi_value exports) {
    const napi_property_descriptor props[] = {
        {"initialize", nullptr, JsInitialize, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startGame", nullptr, JsStartGame, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopGame", nullptr, JsStopGame, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isGameRunning", nullptr, JsIsGameRunning, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"sendKeyEvent", nullptr, JsSendKeyEvent, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"sendMouseButton", nullptr, JsSendMouseButton, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"sendMouseMove", nullptr, JsSendMouseMove, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"sendTouchEvent", nullptr, JsSendTouchEvent, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(props) / sizeof(props[0]), props);
    AttachXComponent(env, exports);
    return exports;
}

napi_module g_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = ModuleInit,
    .nm_modname = "mc4hos_core",
    .nm_priv = nullptr,
    .reserved = {nullptr, nullptr, nullptr, nullptr}
};

} // namespace

extern "C" __attribute__((constructor)) void Mc4hosCoreRegisterModule(void) {
    napi_module_register(&g_module);
}
