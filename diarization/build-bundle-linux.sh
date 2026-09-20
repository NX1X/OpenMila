#!/usr/bin/env bash
# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Builds the Python runtime OpenMila ships for speaker diarization on Linux:
# a relocatable CPython 3.11 with pyannote.audio and its dependencies, minus
# torch, which the app downloads on first use (DiarizationBootstrap).
#
# This is the Linux counterpart of upstream's scripts/build-diarization-bundle.sh,
# with the macOS-only steps removed (no install_name_tool, no codesign) and the
# platform tags changed. Versions match upstream exactly.
#
#   diarization/build-bundle-linux.sh [--output-dir <path>]
#
# The output (~200 MB) is not committed; packaging copies it next to the
# binaries, where Bundle.main looks for it.
set -euo pipefail

PBS_RELEASE="20260510"
PYTHON_VERSION="3.11.15"
PBS_FILENAME="cpython-${PYTHON_VERSION}+${PBS_RELEASE}-x86_64-unknown-linux-gnu-install_only.tar.gz"
PBS_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_RELEASE}/${PBS_FILENAME}"
# From the release's own SHA256SUMS.
PBS_SHA256="14b5843a3492925dab6fdb7cca7d09af83ddf1fe2851f72cf9b1edc8ed2b1db7"

PYANNOTE_VERSION="3.3.2"
TORCH_VERSION="2.2.2"          # pinned; downloaded at runtime by the app
TORCHAUDIO_VERSION="2.2.2"
PIP_PLATFORMS=(manylinux_2_28_x86_64 manylinux2014_x86_64)
PIP_PYTHON_VERSION="3.11"
PIP_IMPLEMENTATION="cp"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT/diarization/out/PythonRuntime"
CACHE_DIR="$ROOT/diarization/cache"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

log() { printf '\n==> %s\n' "$1" >&2; }
die() { echo "error: $1" >&2; exit 1; }

command -v curl >/dev/null || die "curl not found"
command -v tar >/dev/null || die "tar not found"

mkdir -p "$CACHE_DIR"
TARBALL="$CACHE_DIR/$PBS_FILENAME"
if [[ -f "$TARBALL" ]] && echo "$PBS_SHA256  $TARBALL" | sha256sum -c - >/dev/null 2>&1; then
    log "cached CPython tarball verified"
else
    log "downloading $PBS_FILENAME"
    curl -fL --retry 3 --progress-bar -o "$TARBALL.part" "$PBS_URL" >&2
    mv "$TARBALL.part" "$TARBALL"
    echo "$PBS_SHA256  $TARBALL" | sha256sum -c - >/dev/null || die "CPython tarball checksum mismatch"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
log "extracting CPython"
tar xzf "$TARBALL" -C "$TMP"
PY="$TMP/python/bin/python3.11"
[[ -x "$PY" ]] || die "python3.11 missing after extraction"
"$PY" --version >&2

log "resolving pyannote.audio $PYANNOTE_VERSION and its dependencies"
VENV="$TMP/resolve-venv"
"$PY" -m venv "$VENV"
"$VENV/bin/python" -m pip install --quiet --upgrade pip wheel >&2
"$VENV/bin/python" -m pip install --quiet "pyannote.audio==$PYANNOTE_VERSION" \
    "torch==$TORCH_VERSION" "torchaudio==$TORCHAUDIO_VERSION" \
    --index-url https://download.pytorch.org/whl/cpu \
    --extra-index-url https://pypi.org/simple >&2
# torch, torchaudio and the CUDA packages are downloaded by the app instead.
"$VENV/bin/python" -m pip freeze | grep -viE "^(torch|torchaudio|nvidia-|triton)" > "$TMP/frozen.txt"
wc -l < "$TMP/frozen.txt" >&2

log "installing the frozen set into the bundle"
SITE="$TMP/python/site-packages"
mkdir -p "$SITE"
PLATFORM_ARGS=()
for platform in "${PIP_PLATFORMS[@]}"; do PLATFORM_ARGS+=(--platform "$platform"); done
"$VENV/bin/python" -m pip install --quiet --no-deps --target "$SITE" \
    --implementation "$PIP_IMPLEMENTATION" --python-version "$PIP_PYTHON_VERSION" \
    "${PLATFORM_ARGS[@]}" --only-binary=:all: \
    -r "$TMP/frozen.txt" >&2

log "stripping caches and test trees"
find "$SITE" "$TMP/python/lib" -name "__pycache__" -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$SITE" -name "RECORD" -path "*.dist-info/*" -delete 2>/dev/null || true
find "$SITE" -type d \( -name "tests" -o -name "test" \) -prune -exec rm -rf {} + 2>/dev/null || true

cat > "$TMP/python/MANIFEST.txt" <<MANIFEST
OpenMila PythonRuntime bundle (Linux)
Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Build host: $(uname -srm)

python-build-standalone release: $PBS_RELEASE
Python version: $PYTHON_VERSION
PBS tarball: $PBS_FILENAME
PBS sha256: $PBS_SHA256

pyannote.audio target version: $PYANNOTE_VERSION
torch/torchaudio (downloaded at runtime by the app): $TORCH_VERSION/$TORCHAUDIO_VERSION

Installed packages:
$(sed 's/^/  /' "$TMP/frozen.txt")
MANIFEST

log "writing $OUTPUT_DIR"
rm -rf "$OUTPUT_DIR"
mkdir -p "$(dirname "$OUTPUT_DIR")"
mv "$TMP/python" "$TMP/PythonRuntime-python"
mkdir -p "$OUTPUT_DIR"
mv "$TMP/PythonRuntime-python" "$OUTPUT_DIR/python"
du -sh "$OUTPUT_DIR" >&2
log "done"
