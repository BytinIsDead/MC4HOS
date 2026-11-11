/*
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
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
 * the JNI specification exactly — anchors: FindClass=6, GetObjectClass=31,
 * GetMethodID=33, instance call family 34-63, nonvirtual family 64-93,
 * instance fields 94-111, GetStaticMethodID=112, static call family 113-142,
 * static fields 143-161, strings 162-169, object arrays 170-173, primitive
 * arrays 174-213, RegisterNatives=214, GetJavaVM=218, ExceptionCheck=227,
 * GetObjectRefType=231 (232 slots, JNI 1.6 table).
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
    void *reserved0;                                   // 0
    void *reserved1;                                   // 1
    void *reserved2;                                   // 2
    void *reserved3;                                   // 3

    jint (*GetVersion)(JNIEnv *env);                   // 4
    void *DefineClass;                                 // 5
    jclass (*FindClass)(JNIEnv *env, const char *name);// 6
    void *FromReflectedMethod;                         // 7
    void *FromReflectedField;                          // 8
    void *ToReflectedMethod;                           // 9
    void *GetSuperclass;                               // 10
    void *IsAssignableFrom;                            // 11
    void *ToReflectedField;                            // 12
    void *Throw;                                       // 13
    void *ThrowNew;                                    // 14
    jthrowable (*ExceptionOccurred)(JNIEnv *env);      // 15
    void *ExceptionDescribe;                           // 16
    void (*ExceptionClear)(JNIEnv *env);               // 17
    void *FatalError;                                  // 18
    void *PushLocalFrame;                              // 19
    void *PopLocalFrame;                               // 20
    void *NewGlobalRef;                                // 21
    void *DeleteGlobalRef;                             // 22
    void (*DeleteLocalRef)(JNIEnv *env, jobject obj);  // 23
    void *IsSameObject;                                // 24
    void *NewLocalRef;                                 // 25
    void *EnsureLocalCapacity;                         // 26
    void *AllocObject;                                 // 27
    void *NewObject;                                   // 28
    void *NewObjectV;                                  // 29
    void *NewObjectA;                                  // 30
    jclass (*GetObjectClass)(JNIEnv *env, jobject obj);// 31
    void *IsInstanceOf;                                // 32
    jmethodID (*GetMethodID)(JNIEnv *env, jclass cls, const char *name,
                             const char *sig);         // 33

    // 34..63 — instance method call families (Object, Boolean, Byte, Char,
    // Short, Int, Long, Float, Double, Void; plain / va_list / jvalue*).
    // Only the Object trio is typed: ReportException() calls it.
    jobject (*CallObjectMethod)(JNIEnv *env, jobject obj, jmethodID methodID,
                                ...);                  // 34
    jobject (*CallObjectMethodV)(JNIEnv *env, jobject obj, jmethodID methodID,
                                 va_list args);        // 35
    jobject (*CallObjectMethodA)(JNIEnv *env, jobject obj, jmethodID methodID,
                                 const jvalue *args);  // 36
    void *CallBooleanMethod;                           // 37
    void *CallBooleanMethodV;                          // 38
    void *CallBooleanMethodA;                          // 39
    void *CallByteMethod;                              // 40
    void *CallByteMethodV;                             // 41
    void *CallByteMethodA;                             // 42
    void *CallCharMethod;                              // 43
    void *CallCharMethodV;                             // 44
    void *CallCharMethodA;                             // 45
    void *CallShortMethod;                             // 46
    void *CallShortMethodV;                            // 47
    void *CallShortMethodA;                            // 48
    void *CallIntMethod;                               // 49
    void *CallIntMethodV;                              // 50
    void *CallIntMethodA;                              // 51
    void *CallLongMethod;                              // 52
    void *CallLongMethodV;                             // 53
    void *CallLongMethodA;                             // 54
    void *CallFloatMethod;                             // 55
    void *CallFloatMethodV;                            // 56
    void *CallFloatMethodA;                            // 57
    void *CallDoubleMethod;                            // 58
    void *CallDoubleMethodV;                           // 59
    void *CallDoubleMethodA;                           // 60
    void *CallVoidMethod;                              // 61
    void *CallVoidMethodV;                             // 62
    void *CallVoidMethodA;                             // 63

    // 64..93 — CallNonvirtual<Primitive>Method / V / A families
    void *CallNonvirtualObjectMethod;                  // 64
    void *CallNonvirtualObjectMethodV;                 // 65
    void *CallNonvirtualObjectMethodA;                 // 66
    void *CallNonvirtualBooleanMethod;                 // 67
    void *CallNonvirtualBooleanMethodV;                // 68
    void *CallNonvirtualBooleanMethodA;                // 69
    void *CallNonvirtualByteMethod;                    // 70
    void *CallNonvirtualByteMethodV;                   // 71
    void *CallNonvirtualByteMethodA;                   // 72
    void *CallNonvirtualCharMethod;                    // 73
    void *CallNonvirtualCharMethodV;                   // 74
    void *CallNonvirtualCharMethodA;                   // 75
    void *CallNonvirtualShortMethod;                   // 76
    void *CallNonvirtualShortMethodV;                  // 77
    void *CallNonvirtualShortMethodA;                  // 78
    void *CallNonvirtualIntMethod;                     // 79
    void *CallNonvirtualIntMethodV;                    // 80
    void *CallNonvirtualIntMethodA;                    // 81
    void *CallNonvirtualLongMethod;                    // 82
    void *CallNonvirtualLongMethodV;                   // 83
    void *CallNonvirtualLongMethodA;                   // 84
    void *CallNonvirtualFloatMethod;                   // 85
    void *CallNonvirtualFloatMethodV;                  // 86
    void *CallNonvirtualFloatMethodA;                  // 87
    void *CallNonvirtualDoubleMethod;                  // 88
    void *CallNonvirtualDoubleMethodV;                 // 89
    void *CallNonvirtualDoubleMethodA;                 // 90
    void *CallNonvirtualVoidMethod;                    // 91
    void *CallNonvirtualVoidMethodV;                   // 92
    void *CallNonvirtualVoidMethodA;                   // 93

    // 94..102 — instance field getters (Object, Boolean, Byte, Char, Short,
    // Int, Long, Float, Double)
    void *GetObjectField;                              // 94
    void *GetBooleanField;                             // 95
    void *GetByteField;                                // 96
    void *GetCharField;                                // 97
    void *GetShortField;                               // 98
    void *GetIntField;                                 // 99
    void *GetLongField;                                // 100
    void *GetFloatField;                               // 101
    void *GetDoubleField;                              // 102
    // 103..111 — instance field setters
    void *SetObjectField;                              // 103
    void *SetBooleanField;                             // 104
    void *SetByteField;                                // 105
    void *SetCharField;                                // 106
    void *SetShortField;                               // 107
    void *SetIntField;                                 // 108
    void *SetLongField;                                // 109
    void *SetFloatField;                               // 110
    void *SetDoubleField;                              // 111

    jmethodID (*GetStaticMethodID)(JNIEnv *env, jclass cls, const char *name,
                                   const char *sig);   // 112
    // 113..142 — CallStatic<Primitive>Method / V / A families. Only the
    // Void trio is typed: the launcher invokes main() through it.
    void *CallStaticObjectMethod;                      // 113
    void *CallStaticObjectMethodV;                     // 114
    void *CallStaticObjectMethodA;                     // 115
    void *CallStaticBooleanMethod;                     // 116
    void *CallStaticBooleanMethodV;                    // 117
    void *CallStaticBooleanMethodA;                    // 118
    void *CallStaticByteMethod;                        // 119
    void *CallStaticByteMethodV;                       // 120
    void *CallStaticByteMethodA;                       // 121
    void *CallStaticCharMethod;                        // 122
    void *CallStaticCharMethodV;                       // 123
    void *CallStaticCharMethodA;                       // 124
    void *CallStaticShortMethod;                       // 125
    void *CallStaticShortMethodV;                      // 126
    void *CallStaticShortMethodA;                      // 127
    void *CallStaticIntMethod;                         // 128
    void *CallStaticIntMethodV;                        // 129
    void *CallStaticIntMethodA;                        // 130
    void *CallStaticLongMethod;                        // 131
    void *CallStaticLongMethodV;                       // 132
    void *CallStaticLongMethodA;                       // 133
    void *CallStaticFloatMethod;                       // 134
    void *CallStaticFloatMethodV;                      // 135
    void *CallStaticFloatMethodA;                      // 136
    void *CallStaticDoubleMethod;                      // 137
    void *CallStaticDoubleMethodV;                     // 138
    void *CallStaticDoubleMethodA;                     // 139
    void *CallStaticVoidMethod;                        // 140
    void *CallStaticVoidMethodV;                       // 141
    void (*CallStaticVoidMethodA)(JNIEnv *env, jclass cls, jmethodID methodID,
                                  const jvalue *args); // 142

    // 143 — static field id lookup
    void *GetStaticFieldID;                            // 143
    // 144..161 — static field accessors (9 getters, 9 setters)
    void *GetStaticObjectField;                        // 144
    void *GetStaticBooleanField;                       // 145
    void *GetStaticByteField;                          // 146
    void *GetStaticCharField;                          // 147
    void *GetStaticShortField;                         // 148
    void *GetStaticIntField;                           // 149
    void *GetStaticLongField;                          // 150
    void *GetStaticFloatField;                         // 151
    void *GetStaticDoubleField;                        // 152
    void *SetStaticObjectField;                        // 153
    void *SetStaticBooleanField;                       // 154
    void *SetStaticByteField;                          // 155
    void *SetStaticCharField;                          // 156
    void *SetStaticShortField;                         // 157
    void *SetStaticIntField;                           // 158
    void *SetStaticLongField;                          // 159
    void *SetStaticFloatField;                         // 160
    void *SetStaticDoubleField;                        // 161

    // 162..169 — string creation/locking; the UTF trio is typed
    void *NewString;                                   // 162
    void *GetStringLength;                             // 163
    void *GetStringChars;                              // 164
    void *ReleaseStringChars;                          // 165
    jstring (*NewStringUTF)(JNIEnv *env, const char *utf);            // 166
    void *GetStringUTFLength;                          // 167
    const char *(*GetStringUTFChars)(JNIEnv *env, jstring str,
                                     jboolean *isCopy);// 168
    void (*ReleaseStringUTFChars)(JNIEnv *env, jstring str,
                                  const char *chars);  // 169

    // 170..173 — object arrays; New/Set used to assemble main(String[])
    void *GetArrayLength;                              // 170
    jobjectArray (*NewObjectArray)(JNIEnv *env, jsize len, jclass cls,
                                   jobject init);      // 171
    void *GetObjectArrayElement;                       // 172
    void (*SetObjectArrayElement)(JNIEnv *env, jobjectArray array,
                                  jsize index, jobject value); // 173

    // 174..213 — primitive array constructors and element access
    void *NewBooleanArray;                             // 174
    void *NewByteArray;                                // 175
    void *NewCharArray;                                // 176
    void *NewShortArray;                               // 177
    void *NewIntArray;                                 // 178
    void *NewLongArray;                                // 179
    void *NewFloatArray;                               // 180
    void *NewDoubleArray;                              // 181
    void *GetBooleanArrayElements;                     // 182
    void *GetByteArrayElements;                        // 183
    void *GetCharArrayElements;                        // 184
    void *GetShortArrayElements;                       // 185
    void *GetIntArrayElements;                         // 186
    void *GetLongArrayElements;                        // 187
    void *GetFloatArrayElements;                       // 188
    void *GetDoubleArrayElements;                      // 189
    void *ReleaseBooleanArrayElements;                 // 190
    void *ReleaseByteArrayElements;                    // 191
    void *ReleaseCharArrayElements;                    // 192
    void *ReleaseShortArrayElements;                   // 193
    void *ReleaseIntArrayElements;                     // 194
    void *ReleaseLongArrayElements;                    // 195
    void *ReleaseFloatArrayElements;                   // 196
    void *ReleaseDoubleArrayElements;                  // 197
    void *GetBooleanArrayRegion;                       // 198
    void *GetByteArrayRegion;                          // 199
    void *GetCharArrayRegion;                          // 200
    void *GetShortArrayRegion;                         // 201
    void *GetIntArrayRegion;                           // 202
    void *GetLongArrayRegion;                          // 203
    void *GetFloatArrayRegion;                         // 204
    void *GetDoubleArrayRegion;                        // 205
    void *SetBooleanArrayRegion;                       // 206
    void *SetByteArrayRegion;                          // 207
    void *SetCharArrayRegion;                          // 208
    void *SetShortArrayRegion;                         // 209
    void *SetIntArrayRegion;                           // 210
    void *SetLongArrayRegion;                          // 211
    void *SetFloatArrayRegion;                         // 212
    void *SetDoubleArrayRegion;                        // 213

    void *RegisterNatives;                             // 214
    void *UnregisterNatives;                           // 215
    void *MonitorEnter;                                // 216
    void *MonitorExit;                                 // 217
    void *GetJavaVM;                                   // 218
    void *GetStringRegion;                             // 219
    void *GetStringUTFRegion;                          // 220
    void *GetPrimitiveArrayCritical;                   // 221
    void *ReleasePrimitiveArrayCritical;               // 222
    void *GetStringCritical;                           // 223
    void *ReleaseStringCritical;                       // 224
    void *NewWeakGlobalRef;                            // 225
    void *DeleteWeakGlobalRef;                         // 226
    jboolean (*ExceptionCheck)(JNIEnv *env);           // 227
    void *NewDirectByteBuffer;                         // 228
    void *GetDirectBufferAddress;                      // 229
    void *GetDirectBufferCapacity;                     // 230
    void *GetObjectRefType;                            // 231
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
