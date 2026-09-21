#!/usr/bin/env bash
# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Writes a winget manifest for one published OpenMila release into
# out/manifests/n/NX1X/OpenMila/<version>/ (the layout winget-pkgs wants).
# The installer hash comes from the release's SHA256SUMS.
set -euo pipefail

version="${1:?usage: make-manifest.sh <version, e.g. 1.9.5-beta.2+port.3>}"
repo="NX1X/OpenMila"
tag="v$version"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
installer="OpenMila-$version-win64-setup.exe"
url="https://github.com/$repo/releases/download/$tag/$installer"
# `+` is not allowed in a winget version; `.` keeps the ordering.
winget_version="${version//+/.}"
out="$here/out/manifests/n/NX1X/OpenMila/$winget_version"

sums="$(mktemp)"
trap 'rm -f "$sums"' EXIT
gh release download "$tag" --repo "$repo" --pattern SHA256SUMS --output "$sums" --clobber
sha="$(awk -v f="$installer" '$2 == f { print toupper($1) }' "$sums")"
[ -n "$sha" ] || { echo "SHA256SUMS in $tag has no line for $installer" >&2; exit 1; }
notes_url="https://github.com/$repo/releases/tag/${tag//+/%2B}"
today="$(date -u +%Y-%m-%d)"

mkdir -p "$out"
cat > "$out/NX1X.OpenMila.yaml" <<YAML
# yaml-language-server: \$schema=https://aka.ms/winget-manifest.version.1.6.0.schema.json
PackageIdentifier: NX1X.OpenMila
PackageVersion: $winget_version
DefaultLocale: en-US
ManifestType: version
ManifestVersion: 1.6.0
YAML

cat > "$out/NX1X.OpenMila.installer.yaml" <<YAML
# yaml-language-server: \$schema=https://aka.ms/winget-manifest.installer.1.6.0.schema.json
PackageIdentifier: NX1X.OpenMila
PackageVersion: $winget_version
InstallerType: inno
Scope: user
InstallModes:
  - interactive
  - silent
  - silentWithProgress
UpgradeBehavior: install
ReleaseDate: $today
Installers:
  - Architecture: x64
    InstallerUrl: $url
    InstallerSha256: $sha
ManifestType: installer
ManifestVersion: 1.6.0
YAML

cat > "$out/NX1X.OpenMila.locale.en-US.yaml" <<YAML
# yaml-language-server: \$schema=https://aka.ms/winget-manifest.defaultLocale.1.6.0.schema.json
PackageIdentifier: NX1X.OpenMila
PackageVersion: $winget_version
PackageLocale: en-US
Publisher: NX1X LAB
PublisherUrl: https://nx1xlab.dev
PublisherSupportUrl: https://github.com/$repo/issues
PackageName: OpenMila
PackageUrl: https://openmila.nx1xlab.dev
License: Apache-2.0
LicenseUrl: https://github.com/$repo/blob/main/LICENSE
Copyright: Copyright 2026 NX1X. Portions Copyright Island Technology, Inc.
ShortDescription: Local transcription, dictation and meeting notes, on your machine.
Description: |-
  OpenMila records meetings and dictation, transcribes Hebrew and English on
  the machine with whisper.cpp, names the speakers, writes AI summaries through
  a provider you choose (including a fully local one), and exposes transcripts
  to AI tools over MCP. An independent community port of Mila for Linux and
  Windows; not affiliated with or endorsed by Island Technology, Inc.
Tags:
  - transcription
  - dictation
  - whisper
  - speech-to-text
  - hebrew
  - meetings
ReleaseNotesUrl: $notes_url
ManifestType: defaultLocale
ManifestVersion: 1.6.0
YAML

echo "wrote $out"
ls "$out"
