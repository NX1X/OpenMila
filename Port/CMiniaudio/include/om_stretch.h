// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Time stretching for playback speed: changes how fast audio plays without
// changing its pitch. See om_stretch.c for the method.
#ifndef OM_STRETCH_H
#define OM_STRETCH_H

#include <stdint.h>

typedef struct om_stretch om_stretch;

/// Supplies up to `frames` interleaved frames into `dst`, returning how many
/// it wrote. A short return means the source is finished.
typedef uint64_t (*om_stretch_fill)(void *user, float *dst, uint64_t frames);

om_stretch *om_stretch_create(uint32_t sample_rate, uint32_t channels);
void om_stretch_destroy(om_stretch *s);

/// 1.0 plays at the recorded speed, 2.0 twice as fast, 0.5 half as fast.
/// Values outside 0.25 to 4.0 are clamped.
void om_stretch_set_rate(om_stretch *s, double rate);

/// Forgets buffered audio; call after seeking.
void om_stretch_reset(om_stretch *s);

/// Writes `frames` stretched frames into `out`, pulling input through `fill`.
/// Returns the number of frames written, which is short only at the end of the
/// source.
uint64_t om_stretch_read(om_stretch *s, float *out, uint64_t frames,
                         om_stretch_fill fill, void *user);

#endif
