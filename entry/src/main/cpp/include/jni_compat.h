/*
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0-no-copyleft-exception
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef MC4HOS_JNI_COMPAT_H
#define MC4HOS_JNI_COMPAT_H

/**
 * Clean-room, ABI-compatible subset of the JNI Invocation API for MC4HOS.
 *
 * The OpenHarmony NDK sysroot does not ship <jni.h>, and vendoring a JDK's
 * header would import GPLv2+Classpath-Exception text into this MPL-2.0
 * project. This header instead re-declares the published JNI ABI (the
 * interface layout is a stable, publicly specified contract between JVM
 * implementations and embedders) covering only the entry points the
 * launcher calls.
 *
 * ABI safety: the JNIEnv/JavaVM dispatch tables are arrays of uniformly
 * sized function pointers, so unused slots are declared as opaque `void*`
 * placeholders annotated with their documented names. Slot ORDER follows
 * jni.h (JDK 21) exactly — anchors: FindClass=6, GetObjectClass=31,
 * GetMethodID=33, instance call family 34-63, nonvirtual family 64-93,
 * GetFieldID=94, instance fields 95-112, GetStaticMethodID=113,
 * static call family 114-143, static fields 144-162, strings 163-170,
 * object arrays 171-174, primitive arrays 175-214, RegisterNatives=215,
 * GetJavaVM=219, ExceptionCheck=228, GetObjectRefType=232, GetModule=233,
 * IsVirtualThread=234 (235 slots).
 *
 * LP64 targets (aarch64-linux-ohos, x86_64-linux-ohos): fixed-width integer
 * types match the JNI ABI (jint = 32-bit, jlong = 64-bit).
 */

#include <cstdint>
#include <cstddef>
#include <cstdarg>

// -------------------------------------------------------------------------
// constants
// -------------------------------------------------------------------------

#define JNI_OK 0
#define JNI_ERR (-1)
#define JNI_EDETACHED (-2)
#define JNI_EVERSION (-3)
#define JNI_ENOMEM (-4)

#define JNI_TRUE 1
#define JNI_FALSE 0

#define JNI_VERSION_1_1 0x00010001
#define JNI_VERSION_1_2 0x00010002
#define JNI_VERSION_1_4 0x00010004
#define JNI_VERSION_1_6 0x00010006
#define JNI_VERSION_1_8 0x00010008

// The launcher never defines or exports JNI native methods, so export
// decoration is irrelevant; kept as no-ops for signature readability.
#define JNIEXPORT
#define JNICALL

// -------------------------------------------------------------------------
// primitive and handle types
// -------------------------------------------------------------------------

typedef uint8_t jboolean;
typedef int8_t jbyte;
typedef uint16_t jchar;
typedef int16_t jshort;
typedef int32_t jint;
typedef int64_t jlong;
typedef float jfloat;
typedef double jdouble;
typedef jint jsize;

typedef void *jobject;
typedef jobject jclass;
typedef jobject jthrowable;
typedef jobject jstring;
typedef jobject jarray;
typedef jarray jobjectArray;
typedef void *jmethodID;
typedef void *jfieldID;
typedef void *jweak;

typedef union jvalue {
    jboolean z;
    jbyte b;
    jchar c;
    jshort s;
    jint i;
    jlong j;
    jfloat f;
    jdouble d;
    jobject l;
} jvalue;

struct JavaVM;
class JNIEnv;
class JavaVM;

// -------------------------------------------------------------------------
// JNIEnv dispatch table (JNINativeInterface) — full JNI 1.6 slot order.
// `void *Name` placeholders mark documented entry points the launcher does
// not call; they exist purely to preserve offsets.
// -------------------------------------------------------------------------

struct JNINativeInterface {
    void *reserved0;                                                        // 0
    void *reserved1;                                                        // 1
    void *reserved2;                                                        // 2
    void *reserved3;                                                        // 3
    jint (*GetVersion)(JNIEnv *env);                                        // 4
    void *DefineClass;                                                      // 5
    jclass (*FindClass)(JNIEnv *env, const char *name);                     // 6
    void *FromReflectedMethod;                                              // 7
    void *FromReflectedField;                                               // 8
    void *ToReflectedMethod;                                                // 9
    void *GetSuperclass;                                                    // 10
    void *IsAssignableFrom;                                                 // 11
    void *ToReflectedField;                                                 // 12
    void *Throw;                                                            // 13
    void *ThrowNew;                                                         // 14
    jthrowable (*ExceptionOccurred)(JNIEnv *env);                           // 15
    void *ExceptionDescribe;                                                // 16
    void (*ExceptionClear)(JNIEnv *env);                                    // 17
    void *FatalError;                                                       // 18
    void *PushLocalFrame;                                                   // 19
    void *PopLocalFrame;                                                    // 20
    void *NewGlobalRef;                                                     // 21
    void *DeleteGlobalRef;                                                  // 22
    void (*DeleteLocalRef)(JNIEnv *env, jobject obj);                       // 23
    void *IsSameObject;                                                     // 24
    void *NewLocalRef;                                                      // 25
    void *EnsureLocalCapacity;                                              // 26
    void *AllocObject;                                                      // 27
    void *NewObject;                                                        // 28
    void *NewObjectV;                                                       // 29
    void *NewObjectA;                                                       // 30
    jclass (*GetObjectClass)(JNIEnv *env, jobject obj);                     // 31
    void *IsInstanceOf;                                                     // 32
    jmethodID (*GetMethodID)(JNIEnv *env, jclass cls, const char *name,
                              const char *sig);         // 33
    jobject (*CallObjectMethod)(JNIEnv *env, jobject obj, jmethodID methodID,
                                 ...);                  // 34
    jobject (*CallObjectMethodV)(JNIEnv *env, jobject obj, jmethodID methodID,
                                  va_list args);        // 35
    jobject (*CallObjectMethodA)(JNIEnv *env, jobject obj, jmethodID methodID,
                                  const jvalue *args);  // 36
    void *CallBooleanMethod;                                                // 37
    void *CallBooleanMethodV;                                               // 38
    void *CallBooleanMethodA;                                               // 39
    void *CallByteMethod;                                                   // 40
    void *CallByteMethodV;                                                  // 41
    void *CallByteMethodA;                                                  // 42
    void *CallCharMethod;                                                   // 43
    void *CallCharMethodV;                                                  // 44
    void *CallCharMethodA;                                                  // 45
    void *CallShortMethod;                                                  // 46
    void *CallShortMethodV;                                                 // 47
    void *CallShortMethodA;                                                 // 48
    void *CallIntMethod;                                                    // 49
    void *CallIntMethodV;                                                   // 50
    void *CallIntMethodA;                                                   // 51
    void *CallLongMethod;                                                   // 52
    void *CallLongMethodV;                                                  // 53
    void *CallLongMethodA;                                                  // 54
    void *CallFloatMethod;                                                  // 55
    void *CallFloatMethodV;                                                 // 56
    void *CallFloatMethodA;                                                 // 57
    void *CallDoubleMethod;                                                 // 58
    void *CallDoubleMethodV;                                                // 59
    void *CallDoubleMethodA;                                                // 60
    void *CallVoidMethod;                                                   // 61
    void *CallVoidMethodV;                                                  // 62
    void *CallVoidMethodA;                                                  // 63
    void *CallNonvirtualObjectMethod;                                       // 64
    void *CallNonvirtualObjectMethodV;                                      // 65
    void *CallNonvirtualObjectMethodA;                                      // 66
    void *CallNonvirtualBooleanMethod;                                      // 67
    void *CallNonvirtualBooleanMethodV;                                     // 68
    void *CallNonvirtualBooleanMethodA;                                     // 69
    void *CallNonvirtualByteMethod;                                         // 70
    void *CallNonvirtualByteMethodV;                                        // 71
    void *CallNonvirtualByteMethodA;                                        // 72
    void *CallNonvirtualCharMethod;                                         // 73
    void *CallNonvirtualCharMethodV;                                        // 74
    void *CallNonvirtualCharMethodA;                                        // 75
    void *CallNonvirtualShortMethod;                                        // 76
    void *CallNonvirtualShortMethodV;                                       // 77
    void *CallNonvirtualShortMethodA;                                       // 78
    void *CallNonvirtualIntMethod;                                          // 79
    void *CallNonvirtualIntMethodV;                                         // 80
    void *CallNonvirtualIntMethodA;                                         // 81
    void *CallNonvirtualLongMethod;                                         // 82
    void *CallNonvirtualLongMethodV;                                        // 83
    void *CallNonvirtualLongMethodA;                                        // 84
    void *CallNonvirtualFloatMethod;                                        // 85
    void *CallNonvirtualFloatMethodV;                                       // 86
    void *CallNonvirtualFloatMethodA;                                       // 87
    void *CallNonvirtualDoubleMethod;                                       // 88
    void *CallNonvirtualDoubleMethodV;                                      // 89
    void *CallNonvirtualDoubleMethodA;                                      // 90
    void *CallNonvirtualVoidMethod;                                         // 91
    void *CallNonvirtualVoidMethodV;                                        // 92
    void *CallNonvirtualVoidMethodA;                                        // 93
    void *GetFieldID;                                                       // 94
    void *GetObjectField;                                                   // 95
    void *GetBooleanField;                                                  // 96
    void *GetByteField;                                                     // 97
    void *GetCharField;                                                     // 98
    void *GetShortField;                                                    // 99
    void *GetIntField;                                                      // 100
    void *GetLongField;                                                     // 101
    void *GetFloatField;                                                    // 102
    void *GetDoubleField;                                                   // 103
    void *SetObjectField;                                                   // 104
    void *SetBooleanField;                                                  // 105
    void *SetByteField;                                                     // 106
    void *SetCharField;                                                     // 107
    void *SetShortField;                                                    // 108
    void *SetIntField;                                                      // 109
    void *SetLongField;                                                     // 110
    void *SetFloatField;                                                    // 111
    void *SetDoubleField;                                                   // 112
    jmethodID (*GetStaticMethodID)(JNIEnv *env, jclass cls, const char *name,
                                   const char *sig);    // 113
    void *CallStaticObjectMethod;                                           // 114
    void *CallStaticObjectMethodV;                                          // 115
    void *CallStaticObjectMethodA;                                          // 116
    void *CallStaticBooleanMethod;                                          // 117
    void *CallStaticBooleanMethodV;                                         // 118
    void *CallStaticBooleanMethodA;                                         // 119
    void *CallStaticByteMethod;                                             // 120
    void *CallStaticByteMethodV;                                            // 121
    void *CallStaticByteMethodA;                                            // 122
    void *CallStaticCharMethod;                                             // 123
    void *CallStaticCharMethodV;                                            // 124
    void *CallStaticCharMethodA;                                            // 125
    void *CallStaticShortMethod;                                            // 126
    void *CallStaticShortMethodV;                                           // 127
    void *CallStaticShortMethodA;                                           // 128
    void *CallStaticIntMethod;                                              // 129
    void *CallStaticIntMethodV;                                             // 130
    jint (*CallStaticIntMethodA)(JNIEnv *env, jclass cls, jmethodID methodID,
                                  const jvalue *args);  // 131
    void *CallStaticLongMethod;                                             // 132
    void *CallStaticLongMethodV;                                            // 133
    void *CallStaticLongMethodA;                                            // 134
    void *CallStaticFloatMethod;                                            // 135
    void *CallStaticFloatMethodV;                                           // 136
    void *CallStaticFloatMethodA;                                           // 137
    void *CallStaticDoubleMethod;                                           // 138
    void *CallStaticDoubleMethodV;                                          // 139
    void *CallStaticDoubleMethodA;                                          // 140
    void *CallStaticVoidMethod;                                             // 141
    void *CallStaticVoidMethodV;                                            // 142
    void (*CallStaticVoidMethodA)(JNIEnv *env, jclass cls, jmethodID methodID,
                                   const jvalue *args); // 143
    void *GetStaticFieldID;                                                 // 144
    void *GetStaticObjectField;                                             // 145
    void *GetStaticBooleanField;                                            // 146
    void *GetStaticByteField;                                               // 147
    void *GetStaticCharField;                                               // 148
    void *GetStaticShortField;                                              // 149
    void *GetStaticIntField;                                                // 150
    void *GetStaticLongField;                                               // 151
    void *GetStaticFloatField;                                              // 152
    void *GetStaticDoubleField;                                             // 153
    void *SetStaticObjectField;                                             // 154
    void *SetStaticBooleanField;                                            // 155
    void *SetStaticByteField;                                               // 156
    void *SetStaticCharField;                                               // 157
    void *SetStaticShortField;                                              // 158
    void *SetStaticIntField;                                                // 159
    void *SetStaticLongField;                                               // 160
    void *SetStaticFloatField;                                              // 161
    void *SetStaticDoubleField;                                             // 162
    void *NewString;                                                        // 163
    void *GetStringLength;                                                  // 164
    void *GetStringChars;                                                   // 165
    void *ReleaseStringChars;                                               // 166
    jstring (*NewStringUTF)(JNIEnv *env, const char *utf);                  // 167
    void *GetStringUTFLength;                                               // 168
    const char *(*GetStringUTFChars)(JNIEnv *env, jstring str,
                                         jboolean *isCopy);// 169
    void (*ReleaseStringUTFChars)(JNIEnv *env, jstring str,
                                      const char *chars);// 170
    void *GetArrayLength;                                                   // 171
    jobjectArray (*NewObjectArray)(JNIEnv *env, jsize len, jclass cls,
                                      jobject init);    // 172
    void *GetObjectArrayElement;                                            // 173
    void (*SetObjectArrayElement)(JNIEnv *env, jobjectArray array,
                                     jsize index, jobject value);// 174
    void *NewBooleanArray;                                                  // 175
    void *NewByteArray;                                                     // 176
    void *NewCharArray;                                                     // 177
    void *NewShortArray;                                                    // 178
    void *NewIntArray;                                                      // 179
    void *NewLongArray;                                                     // 180
    void *NewFloatArray;                                                    // 181
    void *NewDoubleArray;                                                   // 182
    void *GetBooleanArrayElements;                                          // 183
    void *GetByteArrayElements;                                             // 184
    void *GetCharArrayElements;                                             // 185
    void *GetShortArrayElements;                                            // 186
    void *GetIntArrayElements;                                              // 187
    void *GetLongArrayElements;                                             // 188
    void *GetFloatArrayElements;                                            // 189
    void *GetDoubleArrayElements;                                           // 190
    void *ReleaseBooleanArrayElements;                                      // 191
    void *ReleaseByteArrayElements;                                         // 192
    void *ReleaseCharArrayElements;                                         // 193
    void *ReleaseShortArrayElements;                                        // 194
    void *ReleaseIntArrayElements;                                          // 195
    void *ReleaseLongArrayElements;                                         // 196
    void *ReleaseFloatArrayElements;                                        // 197
    void *ReleaseDoubleArrayElements;                                       // 198
    void *GetBooleanArrayRegion;                                            // 199
    void *GetByteArrayRegion;                                               // 200
    void *GetCharArrayRegion;                                               // 201
    void *GetShortArrayRegion;                                              // 202
    void *GetIntArrayRegion;                                                // 203
    void *GetLongArrayRegion;                                               // 204
    void *GetFloatArrayRegion;                                              // 205
    void *GetDoubleArrayRegion;                                             // 206
    void *SetBooleanArrayRegion;                                            // 207
    void *SetByteArrayRegion;                                               // 208
    void *SetCharArrayRegion;                                               // 209
    void *SetShortArrayRegion;                                              // 210
    void *SetIntArrayRegion;                                                // 211
    void *SetLongArrayRegion;                                               // 212
    void *SetFloatArrayRegion;                                              // 213
    void *SetDoubleArrayRegion;                                             // 214
    void *RegisterNatives;                                                  // 215
    void *UnregisterNatives;                                                // 216
    void *MonitorEnter;                                                     // 217
    void *MonitorExit;                                                      // 218
    void *GetJavaVM;                                                        // 219
    void *GetStringRegion;                                                  // 220
    void *GetStringUTFRegion;                                               // 221
    void *GetPrimitiveArrayCritical;                                        // 222
    void *ReleasePrimitiveArrayCritical;                                    // 223
    void *GetStringCritical;                                                // 224
    void *ReleaseStringCritical;                                            // 225
    void *NewWeakGlobalRef;                                                 // 226
    void *DeleteWeakGlobalRef;                                              // 227
    jboolean (*ExceptionCheck)(JNIEnv *env);                                // 228
    void *NewDirectByteBuffer;                                              // 229
    void *GetDirectBufferAddress;                                           // 230
    void *GetDirectBufferCapacity;                                          // 231
    void *GetObjectRefType;                                                 // 232
    void *GetModule;                                                        // 233
    void *IsVirtualThread;                                                  // 234
};

// -------------------------------------------------------------------------
// JavaVM dispatch table (JNIInvokeInterface) — complete, 8 slots
// -------------------------------------------------------------------------

struct JNIInvokeInterface {
    void *reserved0;
    void *reserved1;
    void *reserved2;
    jint (*DestroyJavaVM)(JavaVM *vm);
    jint (*AttachCurrentThread)(JavaVM *vm, void **penv, void *args);
    jint (*DetachCurrentThread)(JavaVM *vm);
    jint (*GetEnv)(JavaVM *vm, void **penv, jint version);
    jint (*AttachCurrentThreadAsDaemon)(JavaVM *vm, void **penv, void *args);
};

// -------------------------------------------------------------------------
// C++ wrappers (mirror the JNI specification's C++ binding for the used
// subset; wrappers forward through the dispatch tables)
// -------------------------------------------------------------------------

class JNIEnv {
public:
    const JNINativeInterface *functions;

    jint GetVersion() const {
        return functions->GetVersion(const_cast<JNIEnv *>(this));
    }
    jclass FindClass(const char *name) {
        return functions->FindClass(this, name);
    }
    jthrowable ExceptionOccurred() {
        return functions->ExceptionOccurred(this);
    }
    void ExceptionClear() {
        functions->ExceptionClear(this);
    }
    jboolean ExceptionCheck() {
        return functions->ExceptionCheck(this);
    }
    void DeleteLocalRef(jobject obj) {
        functions->DeleteLocalRef(this, obj);
    }
    jclass GetObjectClass(jobject obj) {
        return functions->GetObjectClass(this, obj);
    }
    jmethodID GetMethodID(jclass cls, const char *name, const char *sig) {
        return functions->GetMethodID(this, cls, name, sig);
    }
    jobject CallObjectMethod(jobject obj, jmethodID methodID, ...) {
        va_list args;
        va_start(args, methodID);
        jobject result = functions->CallObjectMethodV(this, obj, methodID, args);
        va_end(args);
        return result;
    }
    jmethodID GetStaticMethodID(jclass cls, const char *name, const char *sig) {
        return functions->GetStaticMethodID(this, cls, name, sig);
    }
    void CallStaticVoidMethodA(jclass cls, jmethodID methodID,
                               const jvalue *args) {
        functions->CallStaticVoidMethodA(this, cls, methodID, args);
    }
    jint CallStaticIntMethodA(jclass cls, jmethodID methodID,
                              const jvalue *args) {
        return functions->CallStaticIntMethodA(this, cls, methodID, args);
    }
    jstring NewStringUTF(const char *utf) {
        return functions->NewStringUTF(this, utf);
    }
    const char *GetStringUTFChars(jstring str, jboolean *isCopy) {
        return functions->GetStringUTFChars(this, str, isCopy);
    }
    void ReleaseStringUTFChars(jstring str, const char *chars) {
        functions->ReleaseStringUTFChars(this, str, chars);
    }
    jobjectArray NewObjectArray(jsize len, jclass cls, jobject init) {
        return functions->NewObjectArray(this, len, cls, init);
    }
    void SetObjectArrayElement(jobjectArray array, jsize index, jobject value) {
        functions->SetObjectArrayElement(this, array, index, value);
    }
};

class JavaVM {
public:
    const JNIInvokeInterface *functions;

    jint AttachCurrentThread(void **penv, void *args) {
        return functions->AttachCurrentThread(this, penv, args);
    }
    jint DetachCurrentThread() {
        return functions->DetachCurrentThread(this);
    }
    jint GetEnv(void **penv, jint version) {
        return functions->GetEnv(this, penv, version);
    }
};

// -------------------------------------------------------------------------
// VM option structures (JNI specification layout)
// -------------------------------------------------------------------------

typedef struct JavaVMOption {
    char *optionString;
    void *extraInfo;
} JavaVMOption;

typedef struct JavaVMInitArgs {
    jint version;
    jint nOptions;
    JavaVMOption *options;
    jboolean ignoreUnrecognized;
} JavaVMInitArgs;

typedef struct JavaVMAttachArgs {
    jint version;
    char *name;
    jobject group;
} JavaVMAttachArgs;

#endif // MC4HOS_JNI_COMPAT_H
