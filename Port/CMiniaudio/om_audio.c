// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.

// Capture only: no decoding, encoding, playback engine or resource manager.
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#define MA_NO_ENGINE
#define MA_NO_NODE_GRAPH
#define MA_NO_RESOURCE_MANAGER
#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#include "om_audio.h"

#include <stdlib.h>
#include <string.h>

struct om_capture {
    ma_context context;
    ma_device device;
    om_samples_callback callback;
    void *user;
    int context_ready;
    int device_ready;
};

static ma_device_type om_type(om_device_kind kind) {
    return kind == OM_DEVICE_LOOPBACK ? ma_device_type_loopback : ma_device_type_capture;
}

static void om_encode_id(const ma_device_id *id, char *out, size_t out_size) {
    // Device ids are a union of backend-specific blobs. Hex keeps them opaque
    // and lossless across the Swift boundary.
    static const char hex[] = "0123456789abcdef";
    const unsigned char *bytes = (const unsigned char *)id;
    size_t n = sizeof(ma_device_id);
    if (n * 2 + 1 > out_size) n = (out_size - 1) / 2;
    for (size_t i = 0; i < n; i++) {
        out[i * 2] = hex[bytes[i] >> 4];
        out[i * 2 + 1] = hex[bytes[i] & 0x0f];
    }
    out[n * 2] = '\0';
}

static int om_decode_id(const char *text, ma_device_id *id) {
    size_t len = strlen(text);
    if (len == 0 || len % 2 != 0 || len / 2 > sizeof(ma_device_id)) return 0;
    memset(id, 0, sizeof(*id));
    unsigned char *bytes = (unsigned char *)id;
    for (size_t i = 0; i < len / 2; i++) {
        int value = 0;
        for (int j = 0; j < 2; j++) {
            char c = text[i * 2 + j];
            int nibble;
            if (c >= '0' && c <= '9') nibble = c - '0';
            else if (c >= 'a' && c <= 'f') nibble = c - 'a' + 10;
            else return 0;
            value = (value << 4) | nibble;
        }
        bytes[i] = (unsigned char)value;
    }
    return 1;
}

int32_t om_list_devices(om_device_kind kind, om_device_info *out, int32_t capacity) {
    ma_context context;
    ma_result result = ma_context_init(NULL, 0, NULL, &context);
    if (result != MA_SUCCESS) return -(int32_t)(result < 0 ? -result : result);

    ma_device_info *playback = NULL, *capture = NULL;
    ma_uint32 playback_count = 0, capture_count = 0;
    result = ma_context_get_devices(&context, &playback, &playback_count, &capture, &capture_count);
    if (result != MA_SUCCESS) {
        ma_context_uninit(&context);
        return -(int32_t)(result < 0 ? -result : result);
    }

    // Loopback records an OUTPUT device, so it enumerates the playback list.
    ma_device_info *list = kind == OM_DEVICE_LOOPBACK ? playback : capture;
    ma_uint32 count = kind == OM_DEVICE_LOOPBACK ? playback_count : capture_count;

    int32_t written = 0;
    for (ma_uint32 i = 0; i < count && written < capacity; i++) {
        om_device_info *info = &out[written++];
        memset(info, 0, sizeof(*info));
        strncpy(info->name, list[i].name, sizeof(info->name) - 1);
        om_encode_id(&list[i].id, info->id, sizeof(info->id));
        info->is_default = list[i].isDefault ? 1 : 0;
    }
    ma_context_uninit(&context);
    return written;
}

static void om_data_callback(ma_device *device, void *output, const void *input, ma_uint32 frames) {
    (void)output;
    om_capture *capture = (om_capture *)device->pUserData;
    if (capture != NULL && capture->callback != NULL && input != NULL && frames > 0) {
        capture->callback(capture->user, (const float *)input, frames);
    }
}

om_capture *om_capture_start(om_device_kind kind, const char *device_id,
                             om_samples_callback callback, void *user, int32_t *error) {
    if (error) *error = MA_SUCCESS;
    om_capture *capture = (om_capture *)calloc(1, sizeof(om_capture));
    if (capture == NULL) { if (error) *error = MA_OUT_OF_MEMORY; return NULL; }
    capture->callback = callback;
    capture->user = user;

    ma_result result = ma_context_init(NULL, 0, NULL, &capture->context);
    if (result != MA_SUCCESS) goto fail;
    capture->context_ready = 1;

    ma_device_id id;
    ma_device_config config = ma_device_config_init(om_type(kind));
    config.capture.format = ma_format_f32;
    config.capture.channels = 1;
    config.sampleRate = 16000;
    config.dataCallback = om_data_callback;
    config.pUserData = capture;
    if (device_id != NULL && device_id[0] != '\0') {
        if (!om_decode_id(device_id, &id)) { result = MA_INVALID_ARGS; goto fail; }
        config.capture.pDeviceID = &id;
    }

    result = ma_device_init(&capture->context, &config, &capture->device);
    if (result != MA_SUCCESS) goto fail;
    capture->device_ready = 1;

    result = ma_device_start(&capture->device);
    if (result != MA_SUCCESS) goto fail;
    return capture;

fail:
    if (error) *error = (int32_t)result;
    om_capture_stop(capture);
    return NULL;
}

void om_capture_stop(om_capture *capture) {
    if (capture == NULL) return;
    // ma_device_uninit stops the device and joins the audio thread, so the
    // callback cannot run after this point.
    if (capture->device_ready) ma_device_uninit(&capture->device);
    if (capture->context_ready) ma_context_uninit(&capture->context);
    free(capture);
}

const char *om_capture_backend_name(const om_capture *capture) {
    if (capture == NULL || !capture->context_ready) return "";
    return ma_get_backend_name(capture->context.backend);
}

const char *om_result_description(int32_t result) {
    return ma_result_description((ma_result)result);
}

// ---- Playback -------------------------------------------------------------

struct om_player {
    ma_decoder decoder;
    ma_device device;
    ma_resampler resampler;
    int decoder_ready, device_ready, resampler_ready;
    double rate;
    ma_uint32 sample_rate;
    ma_uint32 channels;
    ma_uint64 length_frames;
    ma_uint64 cursor_frames;
    int playing;
};

static void om_player_callback(ma_device *device, void *output, const void *input, ma_uint32 frames) {
    (void)input;
    om_player *p = (om_player *)device->pUserData;
    float *out = (float *)output;
    memset(out, 0, (size_t)frames * p->channels * sizeof(float));
    if (!p->playing) return;

    if (p->rate == 1.0) {
        ma_uint64 read = 0;
        ma_decoder_read_pcm_frames(&p->decoder, out, frames, &read);
        p->cursor_frames += read;
        if (read < frames) p->playing = 0;
        return;
    }
    // Pull ceil(frames * rate) source frames and resample to the requested
    // output count.
    ma_uint64 need = (ma_uint64)(frames * p->rate) + 2;
    float *tmp = (float *)malloc((size_t)need * p->channels * sizeof(float));
    if (tmp == NULL) return;
    ma_uint64 read = 0;
    ma_decoder_read_pcm_frames(&p->decoder, tmp, need, &read);
    p->cursor_frames += read;
    ma_uint64 in_frames = read, out_frames = frames;
    ma_resampler_process_pcm_frames(&p->resampler, tmp, &in_frames, out, &out_frames);
    free(tmp);
    if (read < need) p->playing = 0;
}

om_player *om_player_open(const char *path, int32_t *error) {
    if (error) *error = MA_SUCCESS;
    om_player *p = (om_player *)calloc(1, sizeof(om_player));
    if (p == NULL) { if (error) *error = MA_OUT_OF_MEMORY; return NULL; }
    p->rate = 1.0;

    ma_decoder_config dc = ma_decoder_config_init(ma_format_f32, 0, 0);
    ma_result r = ma_decoder_init_file(path, &dc, &p->decoder);
    if (r != MA_SUCCESS) goto fail;
    p->decoder_ready = 1;
    p->sample_rate = p->decoder.outputSampleRate;
    p->channels = p->decoder.outputChannels;
    ma_decoder_get_length_in_pcm_frames(&p->decoder, &p->length_frames);

    ma_resampler_config rc = ma_resampler_config_init(ma_format_f32, p->channels, p->sample_rate, p->sample_rate, ma_resample_algorithm_linear);
    r = ma_resampler_init(&rc, NULL, &p->resampler);
    if (r != MA_SUCCESS) goto fail;
    p->resampler_ready = 1;

    ma_device_config config = ma_device_config_init(ma_device_type_playback);
    config.playback.format = ma_format_f32;
    config.playback.channels = p->channels;
    config.sampleRate = p->sample_rate;
    config.dataCallback = om_player_callback;
    config.pUserData = p;
    r = ma_device_init(NULL, &config, &p->device);
    if (r != MA_SUCCESS) goto fail;
    p->device_ready = 1;
    r = ma_device_start(&p->device);
    if (r != MA_SUCCESS) goto fail;
    return p;
fail:
    if (error) *error = (int32_t)r;
    om_player_close(p);
    return NULL;
}

void om_player_close(om_player *p) {
    if (p == NULL) return;
    if (p->device_ready) ma_device_uninit(&p->device);
    if (p->resampler_ready) ma_resampler_uninit(&p->resampler, NULL);
    if (p->decoder_ready) ma_decoder_uninit(&p->decoder);
    free(p);
}

int32_t om_player_play(om_player *p) { if (!p) return MA_INVALID_ARGS; p->playing = 1; return MA_SUCCESS; }
int32_t om_player_pause(om_player *p) { if (!p) return MA_INVALID_ARGS; p->playing = 0; return MA_SUCCESS; }
int32_t om_player_is_playing(const om_player *p) { return p ? p->playing : 0; }
double om_player_position(om_player *p) { return p ? (double)p->cursor_frames / p->sample_rate : 0; }
double om_player_length(om_player *p) { return p ? (double)p->length_frames / p->sample_rate : 0; }

int32_t om_player_seek(om_player *p, double seconds) {
    if (!p) return MA_INVALID_ARGS;
    ma_uint64 frame = (ma_uint64)(seconds * p->sample_rate);
    if (frame > p->length_frames) frame = p->length_frames;
    ma_result r = ma_decoder_seek_to_pcm_frame(&p->decoder, frame);
    if (r == MA_SUCCESS) p->cursor_frames = frame;
    return (int32_t)r;
}

int32_t om_player_set_rate(om_player *p, double rate) {
    if (!p || rate < 0.5 || rate > 2.0) return MA_INVALID_ARGS;
    p->rate = rate;
    return (int32_t)ma_resampler_set_rate(&p->resampler, (ma_uint32)(p->sample_rate * rate), p->sample_rate);
}
