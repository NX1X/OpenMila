// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Time stretching for playback speed, so 0.5x to 2x keeps voices at their
// natural pitch. Resampling alone (what the player did before) changes the
// pitch with the speed, which upstream's AVAudioUnitTimePitch does not.
//
// The method is WSOLA: cut the input into overlapping windows, and before
// overlap-adding each one, slide it within a small search range to the
// position that correlates best with what has already been written. That is
// what removes the phase discontinuities a plain overlap-add would leave, and
// it is cheap enough for speech at 16 kHz on one core.
//
// Nothing here is specific to a file format or a device: the caller supplies
// input through a fill callback and takes finished frames out.
#include "include/om_stretch.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

// 30 ms windows with 50 % overlap: long enough for pitch periods down to about
// 70 Hz, short enough that a word's attack is not smeared.
#define OM_WINDOW_MS 30
// The window may slide by up to one 10 ms pitch period to find its best fit.
#define OM_SEARCH_MS 10

struct om_stretch {
    uint32_t sample_rate;
    uint32_t channels;
    double rate;             // 1.0 = unchanged, 2.0 = twice as fast
    double read_cursor;      // fractional read position within `input`

    int window;              // frames per window
    int hop;                 // synthesis hop = window / 2
    int search;              // maximum slide, in frames

    float *hann;             // window taper, `window` values

    float *input;            // interleaved source frames
    uint64_t input_frames;   // valid frames in `input`
    uint64_t input_cap;

    float *overlap;          // tail of the previous window, hop frames
    int overlap_valid;

    float *output;           // finished frames not yet handed out
    uint64_t output_frames;
    uint64_t output_read;
    uint64_t output_cap;

    int drained;             // the fill callback has no more input
};

static int om_reserve(float **buffer, uint64_t *cap, uint64_t needed, uint32_t channels) {
    if (*cap >= needed) return 1;
    uint64_t next = *cap ? *cap : 4096;
    while (next < needed) next *= 2;
    float *grown = (float *)realloc(*buffer, (size_t)next * channels * sizeof(float));
    if (grown == NULL) return 0;
    *buffer = grown;
    *cap = next;
    return 1;
}

om_stretch *om_stretch_create(uint32_t sample_rate, uint32_t channels) {
    if (sample_rate == 0 || channels == 0) return NULL;
    om_stretch *s = (om_stretch *)calloc(1, sizeof(om_stretch));
    if (s == NULL) return NULL;
    s->sample_rate = sample_rate;
    s->channels = channels;
    s->rate = 1.0;
    s->window = (int)((uint64_t)sample_rate * OM_WINDOW_MS / 1000);
    if (s->window < 64) s->window = 64;
    s->hop = s->window / 2;
    s->search = (int)((uint64_t)sample_rate * OM_SEARCH_MS / 1000);

    s->hann = (float *)malloc((size_t)s->window * sizeof(float));
    s->overlap = (float *)calloc((size_t)s->hop * channels, sizeof(float));
    if (s->hann == NULL || s->overlap == NULL) { om_stretch_destroy(s); return NULL; }
    for (int i = 0; i < s->window; i++) {
        s->hann[i] = 0.5f - 0.5f * cosf(2.0f * (float)M_PI * (float)i / (float)(s->window - 1));
    }
    return s;
}

void om_stretch_destroy(om_stretch *s) {
    if (s == NULL) return;
    free(s->hann);
    free(s->input);
    free(s->overlap);
    free(s->output);
    free(s);
}

void om_stretch_set_rate(om_stretch *s, double rate) {
    if (s == NULL) return;
    if (rate < 0.25) rate = 0.25;
    if (rate > 4.0) rate = 4.0;
    s->rate = rate;
}

void om_stretch_reset(om_stretch *s) {
    if (s == NULL) return;
    s->input_frames = 0;
    s->read_cursor = 0;
    s->output_frames = 0;
    s->output_read = 0;
    s->overlap_valid = 0;
    s->drained = 0;
    memset(s->overlap, 0, (size_t)s->hop * s->channels * sizeof(float));
}

// Drops input the read cursor has passed, so a long file does not grow the
// buffer without bound.
static void om_trim_input(om_stretch *s) {
    uint64_t keep_from = (uint64_t)s->read_cursor;
    if (keep_from <= (uint64_t)s->search) return;
    uint64_t drop = keep_from - (uint64_t)s->search;
    if (drop == 0 || drop > s->input_frames) return;
    uint64_t remaining = s->input_frames - drop;
    memmove(s->input, s->input + drop * s->channels, (size_t)remaining * s->channels * sizeof(float));
    s->input_frames = remaining;
    s->read_cursor -= (double)drop;
}

static int om_fill_input(om_stretch *s, uint64_t frames, om_stretch_fill fill, void *user) {
    if (s->drained) return 0;
    if (!om_reserve(&s->input, &s->input_cap, s->input_frames + frames, s->channels)) return 0;
    uint64_t got = fill(user, s->input + s->input_frames * s->channels, frames);
    s->input_frames += got;
    if (got < frames) s->drained = 1;
    return got > 0;
}

/// The offset within [-search, +search] whose segment best continues what was
/// written last, by normalised cross-correlation on the first channel.
static int om_best_offset(const om_stretch *s, uint64_t base) {
    if (!s->overlap_valid) return 0;
    int best = 0;
    double best_score = -2.0;
    const int compare = s->hop < 256 ? s->hop : 256;   // enough to align on
    for (int offset = -s->search; offset <= s->search; offset++) {
        int64_t start = (int64_t)base + offset;
        if (start < 0) continue;
        if ((uint64_t)start + (uint64_t)compare > s->input_frames) break;
        double dot = 0, energy = 0;
        for (int i = 0; i < compare; i++) {
            double candidate = s->input[((uint64_t)start + i) * s->channels];
            double previous = s->overlap[(size_t)i * s->channels];
            dot += candidate * previous;
            energy += candidate * candidate;
        }
        double score = energy > 0 ? dot / sqrt(energy) : 0;
        if (score > best_score) { best_score = score; best = offset; }
    }
    return best;
}

// Produces one hop of output: the windowed first half of the chosen segment
// added to the tail kept from the previous window, with the new tail kept for
// the next call.
static int om_emit_hop(om_stretch *s) {
    uint64_t base = (uint64_t)s->read_cursor;
    int offset = om_best_offset(s, base);
    int64_t start = (int64_t)base + offset;
    if (start < 0) start = 0;
    if ((uint64_t)start + (uint64_t)s->window > s->input_frames) return 0;

    if (!om_reserve(&s->output, &s->output_cap, s->output_frames + (uint64_t)s->hop, s->channels)) return 0;
    float *out = s->output + s->output_frames * s->channels;
    const float *segment = s->input + (uint64_t)start * s->channels;

    for (int i = 0; i < s->hop; i++) {
        for (uint32_t c = 0; c < s->channels; c++) {
            size_t index = (size_t)i * s->channels + c;
            float rising = segment[index] * s->hann[i];
            float falling = s->overlap_valid ? s->overlap[index] : 0.0f;
            out[index] = rising + falling;
        }
    }
    // Keep the second half, already tapered, as the next window's tail.
    for (int i = 0; i < s->hop; i++) {
        for (uint32_t c = 0; c < s->channels; c++) {
            size_t source = (size_t)(i + s->hop) * s->channels + c;
            s->overlap[(size_t)i * s->channels + c] = segment[source] * s->hann[i + s->hop];
        }
    }
    s->overlap_valid = 1;
    s->output_frames += (uint64_t)s->hop;
    // The analysis hop is the synthesis hop scaled by the speed; the sliding
    // offset is deliberately not added back, so alignment cannot drift the
    // playback position.
    s->read_cursor += (double)s->hop * s->rate;
    om_trim_input(s);
    return 1;
}

uint64_t om_stretch_read(om_stretch *s, float *out, uint64_t frames,
                         om_stretch_fill fill, void *user) {
    if (s == NULL || out == NULL || fill == NULL) return 0;
    if (s->rate == 1.0) {
        // Nothing to stretch: hand through whatever is buffered, then read
        // straight from the source.
        uint64_t done = 0;
        uint64_t buffered = s->output_frames - s->output_read;
        if (buffered > 0) {
            uint64_t take = buffered < frames ? buffered : frames;
            memcpy(out, s->output + s->output_read * s->channels,
                   (size_t)take * s->channels * sizeof(float));
            s->output_read += take;
            done += take;
        }
        if (done < frames) done += fill(user, out + done * s->channels, frames - done);
        return done;
    }

    uint64_t written = 0;
    while (written < frames) {
        uint64_t buffered = s->output_frames - s->output_read;
        if (buffered > 0) {
            uint64_t take = buffered < (frames - written) ? buffered : (frames - written);
            memcpy(out + written * s->channels, s->output + s->output_read * s->channels,
                   (size_t)take * s->channels * sizeof(float));
            s->output_read += take;
            written += take;
            continue;
        }
        // Everything buffered has been handed out; start the next hop.
        s->output_frames = 0;
        s->output_read = 0;
        uint64_t needed = (uint64_t)s->read_cursor + (uint64_t)s->window + (uint64_t)s->search + 1;
        while (s->input_frames < needed && !s->drained) {
            if (!om_fill_input(s, needed - s->input_frames, fill, user)) break;
        }
        if (!om_emit_hop(s)) break;   // out of input
    }
    return written;
}
