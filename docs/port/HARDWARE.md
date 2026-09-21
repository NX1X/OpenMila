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
| Whole model | Metal GPU | Vulkan when a real device answers, else CPU | same |
| Encoder | CoreML on the ANE | with the model | with the model |
| Build flags | Metal on | `-DGGML_VULKAN=ON` in the release build | `-DGGML_VULKAN=ON`, Ninja generator |
| Runtime decision | `use_gpu = true` | `VulkanAvailability`: GPU, software, or none | same |
| User override | none needed | Settings toggle, or `OPENMILA_DISABLE_GPU=1` | same |

The release packages carry the Vulkan backend on both systems, and the app
asks the machine what it has before using it:

- a discrete, integrated or virtual **GPU** gets the model;
- a **software** Vulkan device (llvmpipe, lavapipe, SwiftShader) is refused,
  because running the model through the CPU pretending to be a GPU is slower
  than whisper.cpp's own CPU backend;
- **no Vulkan** at all is not an error: the CPU path is the fallback and the
  common case.

`openmila-cli gpu` prints the probe's answer, Settings shows it under Models,
and the diagnostic report carries it. The switch is there for a bad driver.

**What has not happened: a measurement.** The decision logic is tested and the
backend is compiled in, but no transcription has been timed on a real GPU on
either system - the development machine has none, and the Windows machine has
not run a model yet. So "Vulkan works" means "it is built, probed and wired",
not "it is x times faster here". Benchmarks come from the beta.

## What the CPU path costs

Transcription with whisper.cpp scales with cores and memory bandwidth. On the
port's development machine (10 vCPU, no GPU) the small fixtures in
`Packages/TranscriptionCore/Fixtures` transcribe faster than real time with
`ggml-tiny`, which is what CI checks. The shipped models are far larger
(`large-v3` for Hebrew, `large-v3-turbo` for English), and no honest number for
them exists yet on this hardware: they have not been benchmarked here, and a
figure invented from another machine's results would be worse than none.
Benchmarking those two models on a desktop CPU, a laptop CPU and one GPU
machine each is still open, and it is what turns "the GPU is wired up" into a
number worth printing.

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

Step 1 has landed. Steps 2 and 3 landed with it: Settings names the backend
and carries the override. What is left is CUDA (4), which stays optional, and
the measurements above.

## What a machine needs

No Mac-class floor exists here, because these systems run on anything. These
are the honest numbers for the shipped models, which are large:

| | Minimum | Comfortable |
|---|---|---|
| CPU | 4 cores, x86-64 | 8+ cores |
| RAM | 8 GB | 16 GB |
| Free disk | 6 GB (app plus both models plus recordings) | 20 GB |
| GPU | none - the CPU path is fully supported | any Vulkan 1.0 device with a working driver |
| Linux | GTK 4, glibc 2.39+ (Ubuntu 24.04 and newer); PipeWire for per-application audio | same, on a GNOME or KDE session |
| Windows | Windows 11, or Windows 10 2004+ for per-application audio | Windows 11 |

Where those numbers come from:

- **Disk**: `ivrit-ai-whisper-large-v3` is 2.9 GB and
  `openai-whisper-large-v3-turbo` is 1.6 GB as installed, plus a ~75 MB
  package and the diarization runtime when it is enabled (torch is downloaded
  on first use and is over 1 GB).
- **RAM**: a `large-v3` model is loaded whole. 8 GB works; it is tight while a
  browser is open.
- **Live AI** has its own floor, inherited from upstream: fewer than 8 logical
  cores or less than 12 GB of RAM counts as the constrained class and the
  rolling summary is gated off (`SystemCapabilities`). Transcription itself is
  not gated.
- **Diarization** runs pyannote on the CPU on every system, including macOS,
  and is the slowest optional feature on a weak machine.
