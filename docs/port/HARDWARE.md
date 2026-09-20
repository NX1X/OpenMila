<!-- Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0. -->
# What runs the models, on each system

Mila on a Mac has two accelerators it can count on, because Apple ships them
in every machine it supports: the GPU through Metal, and the Neural Engine
through a CoreML encoder. whisper.cpp uses Metal for the whole model, and Mila
downloads a `-encoder.mlmodelc` beside each model so the encoder can run on the
ANE. That is why transcription on an M1 laptop is quick without the fans coming
on.

Linux and Windows have no equivalent that is always present. A machine may
have an NVIDIA card, an AMD card, an Intel iGPU, or nothing but a CPU, with
drivers in any state. So the port's rule is: **always work on the CPU, use a
GPU when the machine turns out to have a usable one.**

## Where the port stands today

| | macOS (Mila) | Linux (OpenMila) | Windows (OpenMila) |
|---|---|---|---|
| Whole model | Metal GPU | **CPU** | **CPU** |
| Encoder | CoreML on the ANE | CPU | CPU |
| Build flags | Metal on | whisper.cpp built with no GPU backend | same |
| Runtime switch | `use_gpu = true` | `use_gpu = false` (no `canImport(Metal)`) | same |

So on this release, a GPU changes nothing: a machine with an RTX 4090 and a
machine with none run transcription at the same speed, on the processor. That
is honest but it is not where the port should stay, and it is the largest
performance gap against the Mac build.

The parts of the product that were never GPU work are unaffected: speaker
diarization runs pyannote on the CPU on every system, including macOS, and the
AI summaries are whatever provider the user chose.

## What CPU-only actually costs

Transcription with whisper.cpp scales with cores and memory bandwidth. On the
port's development machine (10 vCPU, no GPU) the small fixtures in
`Packages/TranscriptionCore/Fixtures` transcribe faster than real time with
`ggml-tiny`, which is what CI checks. The shipped models are far larger
(`large-v3` for Hebrew, `large-v3-turbo` for English), and no honest number for
them exists yet on this hardware: they have not been benchmarked here, and a
figure invented from another machine's results would be worse than none.
Benchmarking those two models on a desktop CPU, a laptop CPU and one GPU
machine each is the first task of the GPU work, so that the gain is measured
rather than assumed.

## The plan, in order

1. **Vulkan, both systems.** whisper.cpp's Vulkan backend covers NVIDIA, AMD
   and Intel through one driver-level API, which is the only way to support
   the range of machines Linux and Windows users actually have without three
   builds. Build with `-DGGML_VULKAN=ON` (the CI image already carries
   `libvulkan-dev` and `glslc`), set `use_gpu` off macOS, and keep the CPU path
   as the fallback: if no Vulkan device or driver answers, whisper.cpp falls
   back on its own and the app must not treat that as an error.
2. **Say which backend is in use.** Mila shows a "Preparing Neural Engine"
   banner; the port should show the backend it actually got (Vulkan on a named
   device, or CPU) in Settings and in the diagnostic report. A user whose
   driver is missing should be able to see that in one place rather than
   wonder why it is slow.
3. **A setting to force the CPU.** Vulkan drivers vary in quality; a user who
   hits a driver bug needs a way to turn the GPU off without reinstalling.
4. **CUDA is optional and later.** It is faster than Vulkan on NVIDIA, but it
   means a second build, a large toolkit and per-version compatibility. It is
   worth doing only once Vulkan is shipping and measured.
5. **No ANE equivalent.** Intel NPUs and AMD's XDNA exist, but whisper.cpp has
   no backend for them worth shipping today. `.mlmodelc` downloads stay
   skipped off macOS, as they are now.

Until step 1 lands, `docs/port/PARITY.md` row 19 says CPU on both systems, and
the release notes say the same. Nobody should install OpenMila expecting their
graphics card to be used yet.
