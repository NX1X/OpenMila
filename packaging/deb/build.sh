#!/usr/bin/env bash
# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Builds openmila_<version>_amd64.deb from the same payload as the AppImage:
# the app, the CLI, the MCP helper, the Swift runtime, whisper.cpp, and the
# resources. Installs under /opt/openmila with a launcher on PATH.
#
#   packaging/deb/build.sh [version]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${1:-$(grep -oE 'static let version = "[^"]+"' "$ROOT/Port/App/Sources/AppModel.swift" | sed -E 's/.*"([^"]+)"/\1/')}"
# Debian versions may not contain "+port" segments with uppercase or spaces;
# keep the upstream version and replace the port marker with a tilde-free form.
DEB_VERSION="$(echo "$VERSION" | tr '+' '~' | tr -d ' ')"
OUT="$ROOT/dist"
APPDIR="$OUT/OpenMila.AppDir"
STAGE="$OUT/deb/openmila_${DEB_VERSION}_amd64"

command -v dpkg-deb >/dev/null || { echo "dpkg-deb not found" >&2; exit 1; }
[ -d "$APPDIR/usr/bin" ] || { echo "run packaging/appimage/build.sh first (it produces the payload)" >&2; exit 1; }

rm -rf "$STAGE"
mkdir -p "$STAGE/opt/openmila" "$STAGE/usr/bin" "$STAGE/usr/share/applications" \
         "$STAGE/usr/share/icons/hicolor/256x256/apps" "$STAGE/usr/share/doc/openmila" "$STAGE/DEBIAN"

cp -r "$APPDIR/usr/bin/." "$STAGE/opt/openmila/"
cp -r "$APPDIR/usr/lib" "$STAGE/opt/openmila/lib"
cp "$APPDIR/usr/share/applications/io.github.nx1x.openmila.desktop" "$STAGE/usr/share/applications/"
cp "$APPDIR/usr/share/icons/hicolor/256x256/apps/io.github.nx1x.openmila.png" \
   "$STAGE/usr/share/icons/hicolor/256x256/apps/"
cp "$ROOT/LICENSE" "$ROOT/NOTICE" "$ROOT/THIRD_PARTY_NOTICES.md" "$STAGE/usr/share/doc/openmila/"

# Launchers: the app, and the CLI and MCP helper under their own names.
for name in openmila openmila-cli openmila-mcp; do
  cat > "$STAGE/usr/bin/$name" <<LAUNCH
#!/bin/sh
export LD_LIBRARY_PATH="/opt/openmila/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export OPENMILA_RESOURCES="/opt/openmila"
exec "/opt/openmila/$name" "\$@"
LAUNCH
  chmod 755 "$STAGE/usr/bin/$name"
done

INSTALLED_KB="$(du -sk "$STAGE" | cut -f1)"
cat > "$STAGE/DEBIAN/control" <<CONTROL
Package: openmila
Version: $DEB_VERSION
Section: sound
Priority: optional
Architecture: amd64
Maintainer: NX1X <https://github.com/NX1X/OpenMila>
Installed-Size: $INSTALLED_KB
Depends: libgtk-4-1, libadwaita-1-0, libc6, zlib1g
Recommends: pipewire | pulseaudio, ffmpeg, wl-clipboard | xclip
Suggests: wtype, xdotool, libnotify-bin
Homepage: https://openmila.nx1xlab.dev
Description: Local transcription, dictation and meeting notes
 OpenMila records, dictates and transcribes on your own machine with
 whisper.cpp, with optional speaker diarization and AI summaries. It is a
 port of Mila (macOS) to Linux and Windows, and is not affiliated with or
 endorsed by Island Technology, Inc.
CONTROL

cat > "$STAGE/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q /usr/share/icons/hicolor || true
fi
POSTINST
chmod 755 "$STAGE/DEBIAN/postinst"

dpkg-deb --build --root-owner-group "$STAGE" "$OUT/openmila_${DEB_VERSION}_amd64.deb" >/dev/null
(cd "$OUT" && sha256sum "openmila_${DEB_VERSION}_amd64.deb" > "openmila_${DEB_VERSION}_amd64.deb.sha256")
ls -la "$OUT/openmila_${DEB_VERSION}_amd64.deb"
