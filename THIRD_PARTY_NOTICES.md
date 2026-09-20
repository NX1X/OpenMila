# Third-Party Notices

OpenMila includes, depends on, or downloads at runtime the software listed
here. This file covers the Linux and Windows builds OpenMila distributes.
Mila's own notices for its macOS build are kept verbatim at
[docs/upstream/MILA-THIRD_PARTY_NOTICES.md](docs/upstream/MILA-THIRD_PARTY_NOTICES.md).

Section A lists what OpenMila's packages contain. Section B lists what the app
downloads from the original publisher when a feature is used. Section C lists
what the app uses from the operating system without shipping it.

---

## A. Included in OpenMila's packages

### Mila (Apache-2.0)

The application logic, data model, transcription orchestration, MCP helper
and their tests. See [NOTICE](NOTICE) and [CHANGES.md](CHANGES.md).

- Project: https://github.com/island-io/mila
- Copyright © 2026 Island Technology, Inc. Originally developed by Uri Harduf.

### whisper.cpp and ggml (MIT)

On-device Whisper inference, built from source at the commit Mila pins
(v1.8.4) and shipped as shared libraries.

- Project: https://github.com/ggml-org/whisper.cpp
- Copyright © Georgi Gerganov and whisper.cpp contributors.

### Silero VAD model weights (MIT)

`ggml-silero-v5.1.2.bin`, the voice-activity detector Mila bundles. It is not
listed in Mila's own notices.

- Upstream: https://github.com/snakers4/silero-vad
- Copyright © Silero Team.

### Swift runtime and Foundation (Apache-2.0 with Runtime Library Exception)

`libswiftCore`, `libFoundation*`, `libdispatch` and the other runtime
libraries, shipped so the app runs without a Swift installation.

- Project: https://github.com/swiftlang/swift, https://github.com/swiftlang/swift-corelibs-foundation
- Copyright © Apple Inc. and the Swift project authors.

### miniaudio (MIT-0 or public domain)

Audio capture and playback.

- Project: https://github.com/mackron/miniaudio (version 0.11.25, vendored)
- Copyright © David Reid.

### OpenCombine (MIT)

Stands in for Apple's Combine framework, which Mila's code uses.

- Project: https://github.com/OpenCombine/OpenCombine
- Copyright © Sergej Jaskiewicz and OpenCombine contributors.

### swift-log (Apache-2.0)

- Project: https://github.com/apple/swift-log
- Copyright © Apple Inc. and the Swift project authors.

### swift-crypto (Apache-2.0)

Including its copy of BoringSSL (ISC and OpenSSL-derived licences, reproduced
in the swift-crypto source).

- Project: https://github.com/apple/swift-crypto
- Copyright © Apple Inc. and the Swift project authors.

### SwiftCrossUI (MIT) and its dependencies

The user interface toolkit, with swift-image-formats and its image codecs,
swift-mutex, swift-collections, swift-syntax (build time), swift-atomics,
swift-nio and swift-system (Apache-2.0), plus libpng (libpng licence),
libjpeg-turbo (IJG and BSD-style), libwebp (BSD-3-Clause) and zlib (zlib
licence) where statically linked.

- Project: https://github.com/moreSwift/swift-cross-ui
- Copyright © stackotter and SwiftCrossUI contributors.

### MCP Swift SDK (Apache-2.0, with some contributions under MIT)

Not linked by OpenMila's builds: the port's `openmila-mcp` speaks MCP's stdio
JSON-RPC directly (see CHANGES.md). The entry stays because macOS builds from
upstream's project still use the SDK, and the port tracks the same version
(0.12.1) for protocol compatibility.

- Project: https://github.com/modelcontextprotocol/swift-sdk
- Copyright © Anthropic, PBC and the MCP Swift SDK contributors.

### pyannote/segmentation-3.0 model weights (MIT)

Bundled at `Mila/Resources/DiarizationModels/segmentation-3.0/pytorch_model.bin`. Loaded by the pyannote.audio speaker-diarization pipeline.

- Upstream: https://huggingface.co/pyannote/segmentation-3.0
- License: MIT (per upstream model card).
- Copyright © Hervé Bredin and the pyannote.audio authors.

### pyannote-wespeaker-voxceleb-resnet34-LM model weights

Bundled at `Mila/Resources/DiarizationModels/pyannote-wespeaker-voxceleb-resnet34-LM/pytorch_model.bin`. Loaded as the speaker-embedding model for the diarization pipeline.

- Upstream: https://huggingface.co/pyannote/wespeaker-voxceleb-resnet34-LM
- Upstream WeSpeaker code project: https://github.com/wenet-e2e/wespeaker (Apache-2.0)
- License: **CC-BY-4.0** (Creative Commons Attribution 4.0 International), per the
  HuggingFace model card - it follows the VoxCeleb dataset's terms. Redistribution
  of the weights is permitted with attribution, which this notice provides.
- Copyright © the pyannote.audio / WeSpeaker authors and the VoxCeleb dataset creators.

---

## B. Downloaded by the user from the original publisher at runtime

These components are fetched from the upstream's own CDN or package repository when the relevant feature is used. Mila orchestrates the download but does not redistribute the bytes - the upstream serves them directly. Each component's license attaches at the moment of installation; the upstream packages include their own license texts.

### Whisper model weights - OpenAI (MIT)

`large-v3-turbo` and any other OpenAI Whisper ggml repackagings fetched from `huggingface.co/ggerganov/whisper.cpp`.

- Original project: https://github.com/openai/whisper
- License: MIT - https://github.com/openai/whisper/blob/main/LICENSE
- Copyright © OpenAI.

### Whisper model weights - ivrit.ai (Apache-2.0)

`ivrit-ai/whisper-large-v3-ggml` Hebrew finetune, fetched from `huggingface.co/ivrit-ai`.

- Project: https://www.ivrit.ai / https://huggingface.co/ivrit-ai
- License: Apache-2.0 (per upstream model card).
- Copyright © ivrit.ai.

### PyTorch / torchaudio (BSD-3-Clause)

Wheels fetched on first launch from `download.pytorch.org`. Installed into a user-writable site-packages directory at `<data directory>/Mila/torch-site-packages/`.

- Project: https://pytorch.org
- License: BSD-3-Clause - https://github.com/pytorch/pytorch/blob/main/LICENSE
- Copyright © Meta Platforms and PyTorch contributors.

### pyannote.audio + transitive dependencies

Installed from PyPI via `pip install` into the bundled Python runtime when diarization is used.

| Package | License | Upstream |
|---|---|---|
| `pyannote.audio` | MIT | https://github.com/pyannote/pyannote-audio |
| `speechbrain` | Apache-2.0 | https://github.com/speechbrain/speechbrain |
| `pytorch-lightning` | Apache-2.0 | https://github.com/Lightning-AI/lightning |
| `huggingface_hub` | Apache-2.0 | https://github.com/huggingface/huggingface_hub |
| `soundfile` | BSD-3-Clause | https://github.com/bastibe/python-soundfile |
| `numpy` | BSD-3-Clause | https://github.com/numpy/numpy |

Each package ships its own license text in its installed distribution metadata; the texts above are included by reference rather than reproduced here.

---


## C. Used from the operating system, not shipped

On Linux: GTK 4 and its stack (LGPL-2.1-or-later), libadwaita (LGPL-2.1-or-later),
libsecret and GLib (LGPL-2.1-or-later, for the desktop keyring),
PipeWire or PulseAudio client libraries (MIT / LGPL), libX11 (MIT), and,
when installed, ffmpeg (for AAC and non-WAV audio), `pw-dump`/`pw-record`
(per-application audio capture), `wl-copy`/`xclip`,
`wtype`/`xdotool` and `notify-send`. These are linked or called at run time
from the system's own packages and are not redistributed by OpenMila.

## D. License texts

- MIT: https://opensource.org/license/mit
- MIT-0: https://opensource.org/license/mit-0
- BSD-3-Clause: https://opensource.org/license/bsd-3-clause
- Apache-2.0: https://www.apache.org/licenses/LICENSE-2.0
- CC-BY-4.0: https://creativecommons.org/licenses/by/4.0/

If an attribution here is missing or wrong, please open an issue.
