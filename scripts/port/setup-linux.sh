#!/usr/bin/env bash
# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Makes a fresh Linux machine able to build OpenMila: the apt packages, the
# Swift 6.4.0 toolchain from swift.org (signature checked against the key
# vendored in ci/), and whisper.cpp at the pinned commit. Everything goes to
# $HOME/.local, so it needs no root except for apt. Safe to run again: each
# step skips what is already there.
#
# This is the same recipe as ci/Dockerfile, for a laptop, a cloud sandbox or
# a Codespace. Afterwards:
#
#   source scripts/port/env.sh
#   swift build $OPENMILA_SWIFT_FLAGS
#
# Ubuntu 24.04 and 26.04 are covered (swift.org ships a toolchain for each).
set -euo pipefail

SWIFT_VERSION="${SWIFT_VERSION:-6.4.0}"
SWIFT_SIGNING_FINGERPRINT="52BB7E3DE28A71BE22EC05FFEF80A866B47A981F"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWIFT_HOME="${OPENMILA_SWIFT_HOME:-$HOME/.local/swift-$SWIFT_VERSION}"

log() { printf '\n==> %s\n' "$*"; }

# ---- 1. apt packages ------------------------------------------------------
PACKAGES=(ca-certificates curl gnupg git cmake make gcc g++ pkg-config unzip ffmpeg python3 file zip
          binutils libc6-dev libcurl4-openssl-dev libedit2 libncurses-dev libpython3-dev
          libsqlite3-0 libxml2-dev libz3-dev tzdata zlib1g-dev
          libgtk-4-dev libadwaita-1-dev libpipewire-0.3-dev libsecret-1-dev libdbus-1-dev
          libvulkan-dev glslc libx11-dev)

missing=()
for p in "${PACKAGES[@]}"; do
  dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
done
if [ ${#missing[@]} -eq 0 ]; then
  log "apt packages: all present"
else
  log "apt packages: installing ${#missing[@]} missing"
  if [ "$(id -u)" -eq 0 ]; then
    apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${missing[@]}"
  elif sudo -n true 2>/dev/null; then
    sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${missing[@]}"
  else
    echo "no root and no passwordless sudo. Install these, then run this script again:" >&2
    echo "  sudo apt-get install -y ${missing[*]}" >&2
    exit 1
  fi
fi

# ---- 2. Swift 6.4.0, user-local, signature checked ------------------------
if [ -x "$SWIFT_HOME/usr/bin/swift" ]; then
  log "Swift: already at $SWIFT_HOME ($("$SWIFT_HOME/usr/bin/swift" --version 2>&1 | head -1))"
else
  . /etc/os-release
  case "${VERSION_ID:-}" in
    24.04) platform=ubuntu2404; dotted=ubuntu24.04 ;;
    26.04) platform=ubuntu2604; dotted=ubuntu26.04 ;;
    *) echo "Ubuntu 24.04 or 26.04 expected, got ${PRETTY_NAME:-unknown}" >&2; exit 1 ;;
  esac
  log "Swift $SWIFT_VERSION for $dotted into $SWIFT_HOME"
  base="https://download.swift.org/swift-${SWIFT_VERSION}-release/${platform}/swift-${SWIFT_VERSION}-RELEASE"
  file="swift-${SWIFT_VERSION}-RELEASE-${dotted}.tar.gz"
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  curl -fsSL --retry 4 -o "$work/$file" "$base/$file"
  curl -fsSL --retry 4 -o "$work/$file.sig" "$base/$file.sig"
  # The signing key is vendored, and its fingerprint pinned, so neither a
  # keyserver nor the download page is trusted for who signed the toolchain.
  export GNUPGHOME="$work/gnupg"; mkdir -m 700 "$GNUPGHOME"
  gpg --quiet --import "$ROOT/ci/swift-6.x-release-signing-key.asc"
  gpg --with-colons --fingerprint | grep -q "^fpr:::::::::${SWIFT_SIGNING_FINGERPRINT}:$" \
    || { echo "vendored key does not match the pinned fingerprint" >&2; exit 1; }
  gpg --status-fd 1 --verify "$work/$file.sig" "$work/$file" > "$work/verify.txt" 2>/dev/null || true
  grep -q "VALIDSIG .*${SWIFT_SIGNING_FINGERPRINT}" "$work/verify.txt" \
    || { echo "Swift toolchain signature check failed" >&2; cat "$work/verify.txt" >&2; exit 1; }
  mkdir -p "$SWIFT_HOME"
  tar xzf "$work/$file" -C "$SWIFT_HOME" --strip-components=1
  log "Swift: installed ($("$SWIFT_HOME/usr/bin/swift" --version 2>&1 | head -1))"
fi
export PATH="$SWIFT_HOME/usr/bin:$PATH"

# ---- 3. whisper.cpp at the pinned commit ---------------------------------
log "whisper.cpp at the pinned commit (ci/run.sh whisper)"
cd "$ROOT"
git submodule update --init --recursive Packages/TranscriptionCore/vendor/whisper.cpp
bash ci/run.sh whisper

log "done. Next:"
echo "  source scripts/port/env.sh"
echo "  swift build \$OPENMILA_SWIFT_FLAGS --product openmila-cli"
