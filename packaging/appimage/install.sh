#!/usr/bin/env bash
# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Desktop integration for the OpenMila AppImage: it writes a .desktop entry, the
# icons and the .milaconfig MIME type into the user's own ~/.local/share so the
# AppImage appears in the launcher, keeps its icon in the dock and opens
# .milaconfig files, exactly as the .deb does.
#
#   ./OpenMila-<version>-x86_64.AppImage --install
#   ./OpenMila-<version>-x86_64.AppImage --install --appimage /opt/apps/OpenMila.AppImage
#
# It is optional. The AppImage runs with nothing installed, and this adds no
# system-wide state: everything it writes is under $XDG_DATA_HOME (~/.local/share)
# and is removed again by `--uninstall`, or by packaging/uninstall.sh.
#
# Nothing here needs root, and nothing here is written outside the user's home.
set -euo pipefail

ID="io.github.nx1x.openmila"
SIZES="16 24 32 48 64 128 256 512"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

usage() {
  cat <<'USAGE'
Usage: OpenMila.AppImage --install [options]

  --appimage PATH   the AppImage to point the launcher entry at. Defaults to
                    $APPIMAGE, which the AppImage runtime sets, so this is only
                    needed when the payload was extracted.
  --dry-run         print what would be written and write nothing.
  -h, --help        this text.

Writes, all under $XDG_DATA_HOME (default ~/.local/share):
  applications/io.github.nx1x.openmila.desktop
  icons/hicolor/<size>/apps/io.github.nx1x.openmila.png
  mime/packages/io.github.nx1x.openmila.xml

Undo with: OpenMila.AppImage --uninstall
USAGE
}

APPIMAGE_PATH="${APPIMAGE:-}"
DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --appimage) shift; [ $# -gt 0 ] || { echo "--appimage needs a path" >&2; exit 2; }; APPIMAGE_PATH="$1" ;;
    --dry-run) DRY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

# The payload this script ships in: .../usr/bin/openmila-install, so the share
# tree is one level up. Resolved from the script rather than from $APPDIR so it
# also works when the AppImage has been extracted by hand.
USR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
SRC_DESKTOP="$USR/share/applications/$ID.desktop"
SRC_MIME="$USR/share/mime/packages/$ID.xml"
SRC_ICONS="$USR/share/icons/hicolor"
if [ ! -f "$SRC_DESKTOP" ] || [ ! -f "$SRC_MIME" ] || [ ! -d "$SRC_ICONS" ]; then
  echo "this script installs the desktop files that travel inside the AppImage," >&2
  echo "and they are not beside it ($USR/share). Run it as:" >&2
  echo "  ./OpenMila-<version>-x86_64.AppImage --install" >&2
  exit 1
fi

if [ -z "$APPIMAGE_PATH" ]; then
  echo "cannot tell where the AppImage is: \$APPIMAGE is not set." >&2
  echo "The AppImage runtime sets it, so this usually means the payload was" >&2
  echo "extracted. Pass the path instead: --appimage /path/to/OpenMila.AppImage" >&2
  exit 1
fi
# An absolute path, because a .desktop Exec= is run from an arbitrary directory.
case "$APPIMAGE_PATH" in
  /*) : ;;
  *) APPIMAGE_PATH="$(cd "$(dirname "$APPIMAGE_PATH")" && pwd)/$(basename "$APPIMAGE_PATH")" ;;
esac
if [ ! -x "$APPIMAGE_PATH" ]; then
  echo "not an executable file: $APPIMAGE_PATH" >&2
  echo "chmod +x it first, or pass the right path with --appimage." >&2
  exit 1
fi

DEST_DESKTOP="$DATA_HOME/applications/$ID.desktop"
DEST_MIME="$DATA_HOME/mime/packages/$ID.xml"
DEST_ICONS="$DATA_HOME/icons/hicolor"

say() { echo "$@"; }
run() { if [ "$DRY" -eq 1 ]; then say "would: $*"; else "$@"; fi; }

say "==> OpenMila desktop integration"
say "    AppImage: $APPIMAGE_PATH"
say "    into:     $DATA_HOME"

run mkdir -p "$(dirname "$DEST_DESKTOP")" "$(dirname "$DEST_MIME")"

# The .desktop entry is the one from the payload with Exec and TryExec pointed at
# this AppImage, so the launcher starts the very file the user downloaded. It is
# not rewritten from scratch here on purpose: Name, Comment, Categories,
# MimeType and StartupWMClass stay the single copy in packaging/appimage/build.sh.
if [ "$DRY" -eq 1 ]; then
  say "would write $DEST_DESKTOP (Exec=\"$APPIMAGE_PATH\" %f)"
else
  awk -v exec_line="Exec=\"$APPIMAGE_PATH\" %f" -v try_line="TryExec=$APPIMAGE_PATH" '
    /^Exec=/ { print exec_line; next }
    /^TryExec=/ { next }
    { print }
    END { print try_line }
  ' "$SRC_DESKTOP" > "$DEST_DESKTOP.tmp"
  mv "$DEST_DESKTOP.tmp" "$DEST_DESKTOP"
  chmod 644 "$DEST_DESKTOP"
fi

# Every size the payload carries, so a panel asking for 24 pixels gets a file
# drawn at 24 pixels instead of a downscaled 256.
for size in $SIZES; do
  src="$SRC_ICONS/${size}x${size}/apps/$ID.png"
  [ -f "$src" ] || continue
  run mkdir -p "$DEST_ICONS/${size}x${size}/apps"
  run cp -f "$src" "$DEST_ICONS/${size}x${size}/apps/$ID.png"
done

# The .desktop entry says it handles application/x-milaconfig; that type has to
# exist or a double-clicked .milaconfig is just an unknown file.
run cp -f "$SRC_MIME" "$DEST_MIME"

if [ "$DRY" -eq 0 ]; then
  # Best effort: a desktop without these tools still finds the files on its next
  # scan, so a missing tool is not a failed install.
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q "$DATA_HOME/applications" || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t "$DEST_ICONS" || true
  fi
  if command -v update-mime-database >/dev/null 2>&1; then
    update-mime-database "$DATA_HOME/mime" || true
  fi
  if command -v xdg-mime >/dev/null 2>&1; then
    # xdg-mime records the choice in $XDG_CONFIG_HOME/mimeapps.list, and it
    # cannot create that directory itself.
    mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}"
    xdg-mime default "$ID.desktop" application/x-milaconfig || true
  fi
fi

say ""
say "OpenMila is in your launcher, and .milaconfig files open it."
say "Keep the AppImage where it is: the launcher entry points at"
say "  $APPIMAGE_PATH"
say "To undo this (it removes no recordings, transcripts or settings):"
say "  $APPIMAGE_PATH --uninstall"
