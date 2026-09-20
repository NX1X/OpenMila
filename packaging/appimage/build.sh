#!/usr/bin/env bash
# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Builds OpenMila-<version>-x86_64.AppImage from release builds.
# Bundled: the app, openmila-cli, openmila-mcp, the Swift runtime, whisper.cpp
# libraries, resources. Expected from the system: GTK 4, libadwaita, PipeWire
# or PulseAudio, ffmpeg (optional, for AAC and non-WAV imports).
#   packaging/appimage/build.sh [version]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${1:-$(grep -oE 'static let version = "[^"]+"' "$ROOT/Port/App/Sources/AppModel.swift" | sed -E 's/.*"([^"]+)"/\1/')}"
OUT="$ROOT/dist"
APPDIR="$OUT/OpenMila.AppDir"
SWIFT_HOME="${OPENMILA_SWIFT_HOME:-$HOME/.local/swift-6.4.0}"
WHISPER="${OPENMILA_WHISPER_PREFIX:-$HOME/.local/whisper-9386f23}"
TOOL="$OUT/appimagetool-x86_64.AppImage"
TOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
# appimagetool "continuous" build of 2025-12-04, digest published by GitHub.
TOOL_SHA256="a6d71e2b6cd66f8e8d16c37ad164658985e0cf5fcaa950c90a482890cb9d13e0"

export PATH="$SWIFT_HOME/usr/bin:$PATH"
FLAGS=(-c release -Xcc "-I$WHISPER/include" -Xlinker "-L$WHISPER/lib")

echo "==> release builds"
(cd "$ROOT" && swift build "${FLAGS[@]}" --product openmila-cli >/dev/null && swift build "${FLAGS[@]}" --product openmila-mcp >/dev/null)
(cd "$ROOT/Port/App" && swift build --build-system native -j 3 "${FLAGS[@]}" --product openmila >/dev/null)
ROOT_BIN="$(cd "$ROOT" && swift build "${FLAGS[@]}" --show-bin-path 2>/dev/null | tail -1)"
APP_BIN="$ROOT/Port/App/.build/release"

echo "==> AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib" "$APPDIR/usr/share/openmila" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/256x256/apps"
cp "$APP_BIN/openmila" "$ROOT_BIN/openmila-cli" "$ROOT_BIN/openmila-mcp" "$APPDIR/usr/bin/"
# Resources beside the binaries: that is where Bundle.main looks.
# Credits.html is the macOS About panel; OpenMila ships its own notices.
for entry in ConnectionTestSample.wav ggml-silero-v5.1.2.bin DiarizationModels; do
  cp -r "$ROOT/Mila/Resources/$entry" "$APPDIR/usr/bin/"
done
cp "$WHISPER"/lib/libwhisper.so* "$WHISPER"/lib/libggml*.so* "$APPDIR/usr/lib/"
# Swift runtime: only what the binaries load.
for bin in "$APPDIR"/usr/bin/openmila "$APPDIR"/usr/bin/openmila-cli "$APPDIR"/usr/bin/openmila-mcp; do
  ldd "$bin" | awk '/=> \// {print $3}' | grep -E "swift-6|/swift/linux/" || true
done | sort -u | while read -r lib; do cp -L "$lib" "$APPDIR/usr/lib/"; done
strip --strip-unneeded "$APPDIR"/usr/bin/openmila* "$APPDIR"/usr/lib/*.so* 2>/dev/null || true

cat > "$APPDIR/AppRun" <<'RUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export OPENMILA_RESOURCES="$HERE/usr/bin"
export PATH="$HERE/usr/bin:$PATH"
case "${1:-}" in
  --cli) shift; exec "$HERE/usr/bin/openmila-cli" "$@" ;;
  --mcp) shift; exec "$HERE/usr/bin/openmila-mcp" "$@" ;;
  *) exec "$HERE/usr/bin/openmila" "$@" ;;
esac
RUN
chmod +x "$APPDIR/AppRun"

cat > "$APPDIR/io.github.nx1x.openmila.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=OpenMila
Comment=Local transcription, dictation and meeting notes. A port of Mila for Linux.
Exec=openmila %f
Icon=io.github.nx1x.openmila
Categories=AudioVideo;Audio;Office;Utility;
MimeType=application/x-milaconfig;
Terminal=false
StartupWMClass=openmila
X-AppImage-Version=$VERSION
DESK
cp "$APPDIR/io.github.nx1x.openmila.desktop" "$APPDIR/usr/share/applications/"
python3 "$ROOT/packaging/appimage/placeholder-icon.py" "$APPDIR/usr/share/icons/hicolor/256x256/apps/io.github.nx1x.openmila.png"
cp "$APPDIR/usr/share/icons/hicolor/256x256/apps/io.github.nx1x.openmila.png" "$APPDIR/io.github.nx1x.openmila.png"
cp "$ROOT/LICENSE" "$ROOT/NOTICE" "$ROOT/THIRD_PARTY_NOTICES.md" "$APPDIR/usr/share/openmila/"

echo "==> appimagetool"
if [ ! -f "$TOOL" ]; then curl -fsSL --retry 4 -o "$TOOL" "$TOOL_URL"; fi
echo "$TOOL_SHA256  $TOOL" | sha256sum -c - >/dev/null
chmod +x "$TOOL"
ARCH=x86_64 "$TOOL" --appimage-extract-and-run "$APPDIR" "$OUT/OpenMila-$VERSION-x86_64.AppImage" >/dev/null 2>&1
(cd "$OUT" && sha256sum "OpenMila-$VERSION-x86_64.AppImage" > "OpenMila-$VERSION-x86_64.AppImage.sha256")
ls -la "$OUT/OpenMila-$VERSION-x86_64.AppImage"
