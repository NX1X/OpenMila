#!/usr/bin/env bash
# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Upstream locates bundled files (the connection-test clip, the Silero VAD
# model, diarization weights) through Bundle.main. Off macOS, Bundle.main's
# resource directory is the directory holding the executable, so the packaged
# app ships them beside the binary. For development and tests this script links
# them into a build products directory the same way.
#   scripts/port/link-resources.sh <products-dir>
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST="${1:?usage: link-resources.sh <products-dir>}"
mkdir -p "$DEST"
# Credits.html is the macOS About panel; OpenMila ships its own notices.
for entry in ConnectionTestSample.wav ggml-silero-v5.1.2.bin DiarizationModels; do
  ln -sfn "$ROOT/Mila/Resources/$entry" "$DEST/$entry"
done
