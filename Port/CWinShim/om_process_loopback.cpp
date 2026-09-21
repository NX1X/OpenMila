// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// WASAPI process loopback: one application's audio, not the whole machine.
// See include/om_process_loopback.h for why this exists and why it is C.
// Compiled as C++ for one reason: the interface GUIDs.
//
// The SDK declares IID_IAudioClient and its neighbours EXTERN_C, so INITGUID
// cannot instantiate them, and they are not in uuid.lib either: the link
// failed on all three. In C++ `__uuidof` reads the uuid the SDK header
// already attached to the interface, so the values come from the SDK rather
// than being copied into this file by hand, where a typo would surface as a
// mysterious runtime refusal. The completion handler is also a plain class
// here instead of a hand-written vtable.
//
// Everything this file exports stays C, because Swift is what calls it.
extern "C" {
#include "include/om_process_loopback.h"
}

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
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

/// Receives the answer to ActivateAudioInterfaceAsync, which does not return
/// its result but calls back. A single-use object owned by the stack frame
/// that starts the activation, so the reference count only has to satisfy
/// COM's rules rather than manage a lifetime.
class ActivationHandler : public IActivateAudioInterfaceCompletionHandler {
public:
    explicit ActivationHandler(HANDLE done) : done_(done) {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **object) override {
        if (object == nullptr) return E_POINTER;
        if (riid == __uuidof(IUnknown) || riid == __uuidof(IActivateAudioInterfaceCompletionHandler)) {
            *object = this;
            AddRef();
            return S_OK;
        }
        *object = nullptr;
        return E_NOINTERFACE;
    }

    ULONG STDMETHODCALLTYPE AddRef() override { return (ULONG)InterlockedIncrement(&references_); }
    ULONG STDMETHODCALLTYPE Release() override { return (ULONG)InterlockedDecrement(&references_); }

    HRESULT STDMETHODCALLTYPE ActivateCompleted(IActivateAudioInterfaceAsyncOperation *) override {
        SetEvent(done_);
        return S_OK;
    }

private:
    LONG references_ = 1;
    HANDLE done_;
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
        while (SUCCEEDED(capture->capture->GetNextPacketSize(&available)) &&
               available > 0) {
            BYTE *data = NULL;
            UINT32 frames = 0;
            DWORD flags = 0;
            hr = capture->capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr);
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
            capture->capture->ReleaseBuffer(frames);
        }
    }

    if (initialised) CoUninitialize();
    return 0;
}

// ---------------------------------------------------------------------------
// Starting and stopping.
// ---------------------------------------------------------------------------

extern "C" om_process_loopback *om_process_loopback_start(uint32_t pid,
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

    HANDLE activation_done = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    ActivationHandler handler(activation_done);
    if (activation_done == nullptr) {
        if (error) *error = HRESULT_FROM_WIN32(GetLastError());
        goto fail;
    }

    IActivateAudioInterfaceAsyncOperation *operation = NULL;
    hr = ActivateAudioInterfaceAsync(VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK,
                                     __uuidof(IAudioClient),
                                     &parameter,
                                     &handler,
                                     &operation);
    if (FAILED(hr)) {
        CloseHandle(activation_done);
        if (error) *error = hr;
        goto fail;
    }

    // The engine answers on another thread; ten seconds is far longer than it
    // takes, and finite so a broken audio service cannot hang a recording.
    DWORD waited = WaitForSingleObject(activation_done, 10000);
    CloseHandle(activation_done);
    if (waited != WAIT_OBJECT_0) {
        if (operation) operation->Release();
        if (error) *error = HRESULT_FROM_WIN32(WAIT_TIMEOUT);
        goto fail;
    }

    HRESULT activation_result = E_FAIL;
    IUnknown *activated = NULL;
    hr = operation->GetActivateResult(&activation_result, &activated);
    operation->Release();
    if (FAILED(hr) || FAILED(activation_result) || activated == NULL) {
        if (activated) activated->Release();
        if (error) *error = FAILED(hr) ? hr : activation_result;
        goto fail;
    }
    capture->client = (IAudioClient *)activated;

    // Process loopback requires a shared-timer-driven client with an event,
    // and the buffer duration is expressed in 100 ns units: 200 ms here, which
    // is generous enough to survive a scheduling hiccup.
    hr = capture->client->Initialize(
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
    hr = capture->client->SetEventHandle(capture->event);
    if (FAILED(hr)) { if (error) *error = hr; goto fail; }

    hr = capture->client->GetService(__uuidof(IAudioCaptureClient), (void **)&capture->capture);
    if (FAILED(hr)) { if (error) *error = hr; goto fail; }

    hr = capture->client->Start();
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

extern "C" void om_process_loopback_stop(om_process_loopback *capture) {
    if (capture == NULL) return;

    InterlockedExchange(&capture->running, 0);
    if (capture->event) SetEvent(capture->event);
    if (capture->thread) {
        // The loop wakes at least every 200 ms, so this returns promptly; the
        // timeout is a backstop rather than an expectation.
        WaitForSingleObject(capture->thread, 2000);
        CloseHandle(capture->thread);
    }
    if (capture->client) capture->client->Stop();
    if (capture->capture) capture->capture->Release();
    if (capture->client) capture->client->Release();
    if (capture->event) CloseHandle(capture->event);
    free(capture);
}

extern "C" const char *om_process_loopback_error(int32_t error) {
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
extern "C" om_process_loopback *om_process_loopback_start(uint32_t pid, uint32_t sample_rate, uint32_t channels,
                                               om_loopback_callback callback, void *user,
                                               int32_t *error) {
    (void)pid; (void)sample_rate; (void)channels; (void)callback; (void)user;
    if (error) *error = -1;
    return 0;
}

extern "C" void om_process_loopback_stop(om_process_loopback *capture) { (void)capture; }

extern "C" const char *om_process_loopback_error(int32_t error) {
    (void)error;
    return "process loopback is a Windows feature";
}
#endif
