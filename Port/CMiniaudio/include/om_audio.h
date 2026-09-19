// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Narrow C surface over miniaudio for OpenMila. Swift sees only this header,
// not the 95k-line miniaudio.h. All capture is delivered as 16 kHz mono
// Float32, the format whisper.cpp takes; miniaudio does the device-side
// conversion.
#ifndef OM_AUDIO_H
#define OM_AUDIO_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct om_capture om_capture;

typedef enum {
    OM_DEVICE_CAPTURE = 0,  // microphones, plus monitor sources on PulseAudio/PipeWire
    OM_DEVICE_LOOPBACK = 1  // whole-system output capture (WASAPI only)
} om_device_kind;

typedef struct {
    char name[256];
    char id[256];      // opaque, stable for the session; pass back to om_capture_start
    int32_t is_default;
} om_device_info;

// Called on miniaudio's audio thread with `frame_count` mono samples.
// Must not block, allocate heavily, or call back into om_*.
typedef void (*om_samples_callback)(void *user, const float *samples, uint32_t frame_count);

// Fills up to `capacity` entries; returns the number of devices found, or a
// negative miniaudio result code.
int32_t om_list_devices(om_device_kind kind, om_device_info *out, int32_t capacity);

// `device_id` NULL or "" selects the default device. Returns NULL on failure
// and writes the miniaudio result code to `*error` when `error` is non-NULL.
om_capture *om_capture_start(om_device_kind kind, const char *device_id,
                             om_samples_callback callback, void *user, int32_t *error);

// Stops the device and frees everything. Safe with NULL. After it returns the
// callback will not run again.
void om_capture_stop(om_capture *capture);

// Name of the backend in use ("PulseAudio", "WASAPI", "Null", ...).
const char *om_capture_backend_name(const om_capture *capture);

// Human-readable text for a result code from this API.
const char *om_result_description(int32_t result);

#ifdef __cplusplus
}
#endif

#endif

// ---- Playback -------------------------------------------------------------

typedef struct om_player om_player;

// Opens a WAV/FLAC/MP3 file for playback on the default output device.
// Returns NULL and writes the result code to *error on failure.
om_player *om_player_open(const char *path, int32_t *error);
void om_player_close(om_player *player);
int32_t om_player_play(om_player *player);
int32_t om_player_pause(om_player *player);
int32_t om_player_is_playing(const om_player *player);
// Position and length in seconds.
double om_player_position(om_player *player);
double om_player_length(om_player *player);
int32_t om_player_seek(om_player *player, double seconds);
// Playback rate, 0.5 to 2.0. Changes tempo by resampling; a pitch-preserving
// stretch is layered on top of this in Swift when available.
int32_t om_player_set_rate(om_player *player, double rate);
