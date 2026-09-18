# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Linux build and test environment for OpenMila. Mirrors the developer setup:
# Ubuntu 26.04, Swift 6.4.0 from swift.org (signature verified against a pinned
# key fingerprint), and the system libraries the port links against.
#
# The base image is pinned by digest. Bump tag and digest together:
#   docker buildx imagetools inspect ubuntu:26.04 | grep Digest
FROM ubuntu:26.04@sha256:da6fc2be547864451aa253836dd926da33623312df4a9a243e35dc877c378a78

ARG SWIFT_VERSION=6.4.0
ARG SWIFT_PLATFORM=ubuntu2604
ARG SWIFT_PLATFORM_DOTTED=ubuntu26.04
# swift.org "Swift 6.x Release Signing Key"
ARG SWIFT_SIGNING_FINGERPRINT=52BB7E3DE28A71BE22EC05FFEF80A866B47A981F

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      ca-certificates curl gnupg git cmake make gcc g++ pkg-config unzip ffmpeg \
      binutils libc6-dev libcurl4-openssl-dev libedit2 libncurses-dev libpython3-dev \
      libsqlite3-0 libxml2-dev libz3-dev tzdata zlib1g-dev \
      libgtk-4-dev libadwaita-1-dev libpipewire-0.3-dev libsecret-1-dev libdbus-1-dev \
      libvulkan-dev glslc \
 && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    base="https://download.swift.org/swift-${SWIFT_VERSION}-release/${SWIFT_PLATFORM}/swift-${SWIFT_VERSION}-RELEASE"; \
    file="swift-${SWIFT_VERSION}-RELEASE-${SWIFT_PLATFORM_DOTTED}.tar.gz"; \
    cd /tmp; \
    curl -fsSL --retry 4 -o "$file" "$base/$file"; \
    curl -fsSL --retry 4 -o "$file.sig" "$base/$file.sig"; \
    export GNUPGHOME="$(mktemp -d)"; \
    curl -fsSL https://swift.org/keys/all-keys.asc | gpg --quiet --import -; \
    gpg --status-fd 1 --verify "$file.sig" "$file" > verify.txt 2>/dev/null || true; \
    grep -q "^\[GNUPG:\] VALIDSIG .* ${SWIFT_SIGNING_FINGERPRINT}\$" verify.txt \
      || grep -q "^\[GNUPG:\] VALIDSIG ${SWIFT_SIGNING_FINGERPRINT} " verify.txt \
      || { echo "Swift toolchain signature check failed"; cat verify.txt; exit 1; }; \
    mkdir -p /opt/swift; \
    tar xzf "$file" -C /opt/swift --strip-components=1; \
    rm -rf "$file" "$file.sig" verify.txt "$GNUPGHOME"

ENV PATH=/opt/swift/usr/bin:$PATH

RUN useradd --create-home --uid 1001 builder
USER builder
WORKDIR /work
