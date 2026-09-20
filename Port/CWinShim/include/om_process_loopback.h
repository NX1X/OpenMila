// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Capturing one application's audio on Windows, and nothing else on the
// machine.
//
// Mila records a chosen application through ScreenCaptureKit. Windows has its
// own answer, WASAPI process loopback (Windows 10 2004 and later): you ask
// the audio engine for a client bound to a process id, and it hands you only
// what that process tree plays. It is not exposed through any cross-platform
// audio library, so the port talks to it directly here, and the header stays
// free of Windows types for the reason CWinShim.h explains.
#ifndef OM_PROCESS_LOOPBACK_H
#define OM_PROCESS_LOOPBACK_H

#include <stdint.h>

typedef struct om_process_loopback om_process_loopback;

/// Interleaved float frames at the rate and channel count requested, in
/// capture order. Called on a dedicated thread owned by this module.
typedef void (*om_loopback_callback)(void *user, const float *samples, uint32_t frame_count);

/// Starts capturing what process `pid` and its children are playing.
/// `error` receives an HRESULT when the result is NULL.
om_process_loopback *om_process_loopback_start(uint32_t pid,
                                               uint32_t sample_rate,
                                               uint32_t channels,
                                               om_loopback_callback callback,
                                               void *user,
                                               int32_t *error);

/// Stops the capture and releases everything. Safe with NULL.
void om_process_loopback_stop(om_process_loopback *capture);

/// A human-readable description of an HRESULT this module returned, for a
/// message a user can act on. Never NULL.
const char *om_process_loopback_error(int32_t error);

#endif
