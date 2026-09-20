// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// WASAPI process loopback: one application's audio, not the whole machine.
// See include/om_process_loopback.h for why this exists and why it is C.
#include "include/om_process_loopback.h"

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#include <windows.h>
#include <audioclient.h>
#include <audioclientactivationparams.h>
#include <mmdeviceapi.h>
#include <objbase.h>
#include <stdio.h>
#include <stdlib.h>

struct om_process_loopback {
    IAudioClient *client;
    IAudioCaptureClient *capture;
    HANDLE event;
    HANDLE thread;
    volatile LONG running;
    om_loopback_callback callback;
    void *user;
    uint32_t channels;
};

// ---------------------------------------------------------------------------
// The completion handler.
//
// ActivateAudioInterfaceAsync answers on a callback interface rather than
// returning, so a COM object has to exist to receive it. In C that means
// building the vtable by hand. It is a single-use object owned by the caller,
// so the reference counting is the minimum that keeps COM's rules.
// ---------------------------------------------------------------------------

typedef struct {
    IActivateAudioInterfaceCompletionHandler handler;
    LONG references;
    HANDLE done;
} om_completion_handler;

static HRESULT STDMETHODCALLTYPE handler_query(IActivateAudioInterfaceCompletionHandler *self,
                                               REFIID riid, void **object) {
    if (object == NULL) return E_POINTER;
    if (IsEqualIID(riid, &IID_IUnknown) ||
        IsEqualIID(riid, &IID_IActivateAudioInterfaceCompletionHandler)) {
        *object = self;
        self->lpVtbl->AddRef(self);
        return S_OK;
    }
    *object = NULL;
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE handler_add_ref(IActivateAudioInterfaceCompletionHandler *self) {
    om_completion_handler *handler = (om_completion_handler *)self;
    return (ULONG)InterlockedIncrement(&handler->references);
}

static ULONG STDMETHODCALLTYPE handler_release(IActivateAudioInterfaceCompletionHandler *self) {
    om_completion_handler *handler = (om_completion_handler *)self;
    LONG remaining = InterlockedDecrement(&handler->references);
    return (ULONG)remaining;
}

/// The audio engine calls this when the activation finishes, successfully or
/// not. The result is collected by the waiting thread through the event.
static HRESULT STDMETHODCALLTYPE handler_activate_completed(
    IActivateAudioInterfaceCompletionHandler *self,
    IActivateAudioInterfaceAsyncOperation *operation) {
    (void)operation;
    om_completion_handler *handler = (om_completion_handler *)self;
    SetEvent(handler->done);
    return S_OK;
}

static IActivateAudioInterfaceCompletionHandlerVtbl om_handler_vtbl = {
    handler_query,
    handler_add_ref,
    handler_release,
    handler_activate_completed,
};

// ---------------------------------------------------------------------------
// The capture thread.
// ---------------------------------------------------------------------------

static DWORD WINAPI om_capture_thread(LPVOID parameter) {
    om_process_loopback *capture = (om_process_loopback *)parameter;
    // This thread does its own COM work, and audio callbacks must not be held
    // up by anyone else's apartment.
    HRESULT hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    int initialised = SUCCEEDED(hr);

    while (InterlockedCompareExchange(&capture->running, 1, 1) == 1) {
        // 200 ms is long enough that a stalled engine does not spin the CPU
        // and short enough that stopping is responsive.
        DWORD wait = WaitForSingleObject(capture->event, 200);
        if (wait != WAIT_OBJECT_0) continue;

        UINT32 available = 0;
        while (SUCCEEDED(IAudioCaptureClient_GetNextPacketSize(capture->capture, &available)) &&
               available > 0) {
            BYTE *data = NULL;
            UINT32 frames = 0;
            DWORD flags = 0;
            hr = IAudioCaptureClient_GetBuffer(capture->capture, &data, &frames, &flags, NULL, NULL);
            if (FAILED(hr)) break;

            if (frames > 0 && capture->callback != NULL) {
                if (flags & AUDCLNT_BUFFERFLAGS_SILENT) {
                    // The engine hands back a silent packet rather than
                    // nothing when the application is quiet. Deliver real
                    // zeroes: the mixer and the stall watchdog both count
                    // frames, and skipping them would look like a dead device.
                    size_t count = (size_t)frames * capture->channels;
                    float *silence = (float *)calloc(count, sizeof(float));
                    if (silence != NULL) {
                        capture->callback(capture->user, silence, frames);
                        free(silence);
                    }
                } else {
                    capture->callback(capture->user, (const float *)data, frames);
                }
            }
            IAudioCaptureClient_ReleaseBuffer(capture->capture, frames);
        }
    }

    if (initialised) CoUninitialize();
    return 0;
}

// ---------------------------------------------------------------------------
// Starting and stopping.
// ---------------------------------------------------------------------------

om_process_loopback *om_process_loopback_start(uint32_t pid,
                                               uint32_t sample_rate,
                                               uint32_t channels,
                                               om_loopback_callback callback,
                                               void *user,
                                               int32_t *error) {
    if (error) *error = 0;
    if (callback == NULL || channels == 0 || sample_rate == 0) {
        if (error) *error = E_INVALIDARG;
        return NULL;
    }

    HRESULT hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    int com_initialised = SUCCEEDED(hr) || hr == RPC_E_CHANGED_MODE;

    om_process_loopback *capture = (om_process_loopback *)calloc(1, sizeof(om_process_loopback));
    if (capture == NULL) {
        if (error) *error = E_OUTOFMEMORY;
        if (com_initialised && hr != RPC_E_CHANGED_MODE) CoUninitialize();
        return NULL;
    }
    capture->channels = channels;
    capture->callback = callback;
    capture->user = user;

    // What the port wants everywhere: 16 kHz mono float, whisper's format.
    WAVEFORMATEX format;
    ZeroMemory(&format, sizeof(format));
    format.wFormatTag = WAVE_FORMAT_IEEE_FLOAT;
    format.nChannels = (WORD)channels;
    format.nSamplesPerSec = sample_rate;
    format.wBitsPerSample = 32;
    format.nBlockAlign = (WORD)(channels * sizeof(float));
    format.nAvgBytesPerSec = sample_rate * format.nBlockAlign;
    format.cbSize = 0;

    AUDIOCLIENT_ACTIVATION_PARAMS activation;
    ZeroMemory(&activation, sizeof(activation));
    activation.ActivationType = AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK;
    activation.ProcessLoopbackParams.TargetProcessId = (DWORD)pid;
    // The tree, not the one process: a browser plays through a child process,
    // so including only the parent would capture silence from Chrome or Edge.
    activation.ProcessLoopbackParams.ProcessLoopbackMode =
        PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE;

    PROPVARIANT parameter;
    PropVariantInit(&parameter);
    parameter.vt = VT_BLOB;
    parameter.blob.cbSize = sizeof(activation);
    parameter.blob.pBlobData = (BYTE *)&activation;

    om_completion_handler handler;
    ZeroMemory(&handler, sizeof(handler));
    handler.handler.lpVtbl = &om_handler_vtbl;
    handler.references = 1;
    handler.done = CreateEventW(NULL, FALSE, FALSE, NULL);
    if (handler.done == NULL) {
        if (error) *error = HRESULT_FROM_WIN32(GetLastError());
        goto fail;
    }

    IActivateAudioInterfaceAsyncOperation *operation = NULL;
    hr = ActivateAudioInterfaceAsync(VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK,
                                     &IID_IAudioClient,
                                     &parameter,
                                     &handler.handler,
                                     &operation);
    if (FAILED(hr)) {
        CloseHandle(handler.done);
        if (error) *error = hr;
        goto fail;
    }

    // The engine answers on another thread; ten seconds is far longer than it
    // takes, and finite so a broken audio service cannot hang a recording.
    DWORD waited = WaitForSingleObject(handler.done, 10000);
    CloseHandle(handler.done);
    if (waited != WAIT_OBJECT_0) {
        if (operation) IUnknown_Release((IUnknown *)operation);
        if (error) *error = HRESULT_FROM_WIN32(WAIT_TIMEOUT);
        goto fail;
    }

    HRESULT activation_result = E_FAIL;
    IUnknown *activated = NULL;
    hr = IActivateAudioInterfaceAsyncOperation_GetActivateResult(operation, &activation_result, &activated);
    IUnknown_Release((IUnknown *)operation);
    if (FAILED(hr) || FAILED(activation_result) || activated == NULL) {
        if (activated) IUnknown_Release(activated);
        if (error) *error = FAILED(hr) ? hr : activation_result;
        goto fail;
    }
    capture->client = (IAudioClient *)activated;

    // Process loopback requires a shared-timer-driven client with an event,
    // and the buffer duration is expressed in 100 ns units: 200 ms here, which
    // is generous enough to survive a scheduling hiccup.
    hr = IAudioClient_Initialize(capture->client,
                                 AUDCLNT_SHAREMODE_SHARED,
                                 AUDCLNT_STREAMFLAGS_LOOPBACK |
                                 AUDCLNT_STREAMFLAGS_EVENTCALLBACK |
                                 AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM |
                                 AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
                                 2000000, 0, &format, NULL);
    if (FAILED(hr)) {
        if (error) *error = hr;
        goto fail;
    }

    capture->event = CreateEventW(NULL, FALSE, FALSE, NULL);
    if (capture->event == NULL) {
        if (error) *error = HRESULT_FROM_WIN32(GetLastError());
        goto fail;
    }
    hr = IAudioClient_SetEventHandle(capture->client, capture->event);
    if (FAILED(hr)) { if (error) *error = hr; goto fail; }

    hr = IAudioClient_GetService(capture->client, &IID_IAudioCaptureClient, (void **)&capture->capture);
    if (FAILED(hr)) { if (error) *error = hr; goto fail; }

    hr = IAudioClient_Start(capture->client);
    if (FAILED(hr)) { if (error) *error = hr; goto fail; }

    InterlockedExchange(&capture->running, 1);
    capture->thread = CreateThread(NULL, 0, om_capture_thread, capture, 0, NULL);
    if (capture->thread == NULL) {
        InterlockedExchange(&capture->running, 0);
        if (error) *error = HRESULT_FROM_WIN32(GetLastError());
        goto fail;
    }
    return capture;

fail:
    om_process_loopback_stop(capture);
    return NULL;
}

void om_process_loopback_stop(om_process_loopback *capture) {
    if (capture == NULL) return;

    InterlockedExchange(&capture->running, 0);
    if (capture->event) SetEvent(capture->event);
    if (capture->thread) {
        // The loop wakes at least every 200 ms, so this returns promptly; the
        // timeout is a backstop rather than an expectation.
        WaitForSingleObject(capture->thread, 2000);
        CloseHandle(capture->thread);
    }
    if (capture->client) IAudioClient_Stop(capture->client);
    if (capture->capture) IAudioCaptureClient_Release(capture->capture);
    if (capture->client) IAudioClient_Release(capture->client);
    if (capture->event) CloseHandle(capture->event);
    free(capture);
}

const char *om_process_loopback_error(int32_t error) {
    HRESULT hr = (HRESULT)error;
    // HRESULT_FROM_WIN32 is an inline function here, not a constant, so these
    // two cannot be case labels.
    if (hr == HRESULT_FROM_WIN32(WAIT_TIMEOUT)) return "the audio engine did not answer";
    if (hr == HRESULT_FROM_WIN32(ERROR_NOT_FOUND)) return "that application is no longer running";

    switch (hr) {
    case S_OK: return "no error";
    case E_INVALIDARG: return "the capture was asked for an impossible format";
    case E_OUTOFMEMORY: return "out of memory";
    case AUDCLNT_E_DEVICE_INVALIDATED: return "the audio device went away";
    case AUDCLNT_E_SERVICE_NOT_RUNNING: return "the Windows audio service is not running";
    case AUDCLNT_E_UNSUPPORTED_FORMAT: return "the audio engine refused 16 kHz mono float";
    default: return "the audio engine refused the request";
    }
}
#else
// Every other system builds this to nothing: the port's other backends cover
// them, and C forbids an empty translation unit.
om_process_loopback *om_process_loopback_start(uint32_t pid, uint32_t sample_rate, uint32_t channels,
                                               om_loopback_callback callback, void *user,
                                               int32_t *error) {
    (void)pid; (void)sample_rate; (void)channels; (void)callback; (void)user;
    if (error) *error = -1;
    return 0;
}

void om_process_loopback_stop(om_process_loopback *capture) { (void)capture; }

const char *om_process_loopback_error(int32_t error) {
    (void)error;
    return "process loopback is a Windows feature";
}
#endif
