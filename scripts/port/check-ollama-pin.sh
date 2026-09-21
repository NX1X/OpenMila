#!/usr/bin/env bash
# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# The local AI runtime is Ollama at a pinned release, and the digests in
# Port/LocalAI/ManagedOllama.swift are the trust anchor: the app runs nothing
# that does not match them. Ollama publishes no signatures or attestations,
# only a sha256sum.txt beside the assets, so the one check available after
# the fact is whether the vendor still says what the pin says. A drift means
# the release's assets were replaced, which is exactly the case a pin exists
# to catch; it fails this script, and CI turns that into a red weekly run.
#
# Also refuses a pin on a pre-release, and warns when a newer stable exists.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_file="$here/../../Port/LocalAI/ManagedOllama.swift"

version="$(grep -oE 'version: "[0-9]+\.[0-9]+\.[0-9]+"' "$source_file" | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
[ -n "$version" ] || { echo "no pinned version found in $source_file" >&2; exit 1; }
tag="v$version"

pinned_linux="$(grep -A3 'ollama-linux-amd64.tar.zst' "$source_file" | grep -oE 'sha256: "[0-9a-f]{64}"' | head -1 | grep -oE '[0-9a-f]{64}')"
pinned_windows="$(grep -A3 'ollama-windows-amd64.zip' "$source_file" | grep -oE 'sha256: "[0-9a-f]{64}"' | head -1 | grep -oE '[0-9a-f]{64}')"
[ -n "$pinned_linux" ] && [ -n "$pinned_windows" ] || { echo "could not read both pinned digests" >&2; exit 1; }

echo "pinned: ollama $tag"
echo "  linux   $pinned_linux"
echo "  windows $pinned_windows"

release="$(gh api "repos/ollama/ollama/releases/tags/$tag")"
prerelease="$(printf '%s' "$release" | python3 -c 'import json,sys; print(json.load(sys.stdin)["prerelease"])')"
if [ "$prerelease" != "False" ]; then
  echo "::error::the pinned release $tag is a pre-release; the pin must be a stable release" >&2
  exit 1
fi

sums="$(mktemp)"; trap 'rm -f "$sums"' EXIT
gh release download "$tag" --repo ollama/ollama --pattern sha256sum.txt --output "$sums" --clobber
published_linux="$(awk '/ollama-linux-amd64\.tar\.zst$/ { print $1 }' "$sums")"
published_windows="$(awk '/ollama-windows-amd64\.zip$/ { print $1 }' "$sums")"

status=0
if [ "$published_linux" != "$pinned_linux" ]; then
  echo "::error::the vendor's digest for ollama-linux-amd64.tar.zst at $tag no longer matches the pin ($published_linux vs $pinned_linux)" >&2
  status=1
fi
if [ "$published_windows" != "$pinned_windows" ]; then
  echo "::error::the vendor's digest for ollama-windows-amd64.zip at $tag no longer matches the pin ($published_windows vs $pinned_windows)" >&2
  status=1
fi
[ $status -eq 0 ] && echo "the vendor still publishes the pinned digests for $tag"

newest="$(gh api "repos/ollama/ollama/releases?per_page=10" --jq '[.[]|select(.prerelease==false and .draft==false)][0].tag_name')"
if [ "$newest" != "$tag" ]; then
  echo "::notice::a newer stable Ollama exists: $newest (pinned: $tag). Bumping is a deliberate commit: stable only, at least seven days old, digests copied from sha256sum.txt and checked against a fresh download."
fi
exit $status
