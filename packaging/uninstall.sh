#!/usr/bin/env bash
# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Removes OpenMila from a Linux account, and keeps what the user made.
#
#   ./OpenMila-<version>-x86_64.AppImage --uninstall     (portable / AppImage)
#   openmila-uninstall                                   (installed by the .deb)
#   packaging/uninstall.sh                               (from a checkout)
#
# What it removes: the launcher entry, the icons, the .milaconfig association,
# the autostart entry, the MCP registration, the regenerable cache and - in the
# AppImage case - the AppImage file itself.
#
# What it keeps, always, unless you explicitly ask otherwise: your recordings,
# transcripts, downloaded models and settings. They are yours, they are not
# regenerable, and an uninstall is not a request to destroy them. `--purge` is
# how you ask, and even that asks again before it touches recordings.
#
# It only ever writes inside your home directory. The .deb's files under /opt
# and /usr belong to the package manager, so this script names the apt command
# rather than deleting them behind dpkg's back.
set -euo pipefail

ID="io.github.nx1x.openmila"
SIZES="16 24 32 48 64 128 256 512"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

# The app's own locations. "Mila", not "openmila": the data directory keeps
# upstream's name because the MCP helper and the shared code resolve it by that
# name. See Port/LinuxPlatform/LinuxAppPaths.swift.
DATA_DIR="$DATA_HOME/Mila"
CACHE_DIR="$CACHE_HOME/openmila"
LOG_DIR="$STATE_HOME/openmila"
DESKTOP_FILE="$DATA_HOME/applications/$ID.desktop"
MIME_FILE="$DATA_HOME/mime/packages/$ID.xml"
ICON_ROOT="$DATA_HOME/icons/hicolor"
AUTOSTART_FILE="$CONFIG_HOME/autostart/$ID.desktop"
MIMEAPPS="$CONFIG_HOME/mimeapps.list"

PURGE=0
PURGE_MODELS=0
ASSUME_YES=0
KEEP_APPIMAGE=0
DRY=0

usage() {
  cat <<'USAGE'
Usage: openmila-uninstall [options]

  (no options)      Remove OpenMila and keep everything you made: the launcher
                    entry, icons, .milaconfig association, autostart entry, MCP
                    registration, the cache, and the AppImage itself.

  --purge-models    Also delete the downloaded Whisper models and the diarization
                    Python packages. Several GB, re-downloadable, safe to lose.

  --purge           Also delete settings, logs, AND your recordings and
                    transcripts. Irreversible. Asks for a typed confirmation
                    before it touches recordings.

  --keep-appimage   Do not delete the AppImage file, only the integration.
  --yes             Do not ask anything. With --purge this deletes recordings
                    without a further prompt.
  --dry-run         Print what would be removed and remove nothing.
  -h, --help        This text.

Never touched without --purge:
  ~/.local/share/Mila     recordings, transcripts, models, the MCP contracts
  ~/.config               settings
  ~/.local/state/openmila logs
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --purge) PURGE=1 ;;
    --purge-models) PURGE_MODELS=1 ;;
    --keep-appimage) KEEP_APPIMAGE=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --dry-run|-n) DRY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

# Every path this script deletes has to be inside $HOME. A bug that computed an
# empty variable would otherwise hand rm -rf a root-level path.
inside_home() {
  case "$1" in
    "$HOME"/*) return 0 ;;
    *) return 1 ;;
  esac
}

remove() {
  local path="$1"
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then return 0; fi
  if ! inside_home "$path"; then
    # Said, and skipped, rather than fatal: one surprising path (an XDG variable
    # pointing somewhere unusual) must not strand the rest of the cleanup.
    echo "skipped, because it is outside your home: $path" >&2
    return 0
  fi
  if [ "$DRY" -eq 1 ]; then
    echo "would remove: $path"
  else
    rm -rf -- "$path"
    echo "removed: $path"
  fi
}

confirm() {
  local prompt="$1"
  if [ "$ASSUME_YES" -eq 1 ]; then return 0; fi
  if [ ! -t 0 ]; then
    echo "not a terminal, so nothing was asked and nothing was deleted: $prompt" >&2
    echo "Pass --yes if you really mean it." >&2
    return 1
  fi
  local reply
  printf '%s [y/N] ' "$prompt"
  read -r reply
  case "$reply" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# Recordings and transcripts cannot be re-downloaded, re-generated or recovered,
# so this one asks for the words rather than a keystroke.
confirm_typed() {
  local phrase="delete my recordings"
  if [ "$ASSUME_YES" -eq 1 ]; then return 0; fi
  if [ ! -t 0 ]; then
    echo "not a terminal: your recordings were kept. Pass --yes to purge without asking." >&2
    return 1
  fi
  local reply
  echo "This deletes every recording and transcript in $DATA_DIR."
  printf 'Type "%s" to confirm, or anything else to keep them: ' "$phrase"
  read -r reply
  [ "$reply" = "$phrase" ]
}

# The AppImage the launcher entry points at, read before that entry is removed.
appimage_path() {
  local exec_line=""
  if [ -f "$DESKTOP_FILE" ]; then
    exec_line="$(sed -n 's/^Exec=//p' "$DESKTOP_FILE" | head -n 1)"
    exec_line="${exec_line% %[fFuU]}"
    exec_line="${exec_line%\"}"
    exec_line="${exec_line#\"}"
  fi
  case "$exec_line" in
    *.AppImage) echo "$exec_line"; return 0 ;;
  esac
  case "${APPIMAGE:-}" in
    *.AppImage) echo "$APPIMAGE"; return 0 ;;
  esac
  echo ""
}

# A .milaconfig handler the user (or install.sh, through xdg-mime) recorded in
# mimeapps.list. Dropping only our own entry leaves any other handler alone.
clean_mimeapps() {
  local file="$1"
  [ -f "$file" ] || return 0
  grep -q "$ID.desktop" "$file" || return 0
  if [ "$DRY" -eq 1 ]; then
    echo "would drop $ID.desktop from $file"
    return 0
  fi
  awk -v id="$ID.desktop" '
    /^\[/ { print; next }
    index($0, id) == 0 { print; next }
    {
      eq = index($0, "=")
      if (eq == 0) { print; next }
      key = substr($0, 1, eq)
      n = split(substr($0, eq + 1), parts, ";")
      out = ""
      for (i = 1; i <= n; i++) {
        if (parts[i] != "" && parts[i] != id) { out = out parts[i] ";" }
      }
      if (out != "") { print key out }
    }
  ' "$file" > "$file.openmila-tmp"
  mv "$file.openmila-tmp" "$file"
  echo "updated: $file"
}

APPIMAGE_FILE="$(appimage_path)"

echo "==> Removing OpenMila for $(id -un)"
if [ "$DRY" -eq 1 ]; then echo "    (dry run: nothing will be deleted)"; fi

# 1. The desktop integration: launcher entry, icons, MIME type, associations.
remove "$DESKTOP_FILE"
remove "$MIME_FILE"
for size in $SIZES; do
  remove "$ICON_ROOT/${size}x${size}/apps/$ID.png"
done
clean_mimeapps "$MIMEAPPS"

# 2. The autostart entry, if one was ever made.
remove "$AUTOSTART_FILE"

# 3. The MCP registration, so an AI client stops offering a helper that is gone.
#    It is a line in the client's own config, not ours, so this asks the client
#    to remove it rather than editing someone else's file.
if command -v claude >/dev/null 2>&1; then
  if [ "$DRY" -eq 1 ]; then
    echo "would run: claude mcp remove openmila"
  else
    if claude mcp remove openmila >/dev/null 2>&1; then
      echo "removed: the openmila MCP server from Claude Code"
    fi
  fi
else
  echo "note: if you registered the MCP helper with an AI client, remove it there"
  echo "      (Claude Code: claude mcp remove openmila)"
fi

# 4. The cache. Regenerable by definition, and it is not where anything the user
#    made is kept - with one exception. local-ai/ holds the model server and the
#    language models the user chose to download from inside the app, several
#    gigabytes that took a while to arrive. Re-downloadable, but not something a
#    plain uninstall should throw away unasked: it stays, and goes with --purge.
if [ -d "$CACHE_DIR" ]; then
  for entry in "$CACHE_DIR"/* "$CACHE_DIR"/.[!.]*; do
    [ -e "$entry" ] || continue
    case "$(basename "$entry")" in
      local-ai) echo "kept: $entry (local AI runtime and models; --purge removes it)" ;;
      *) remove "$entry" ;;
    esac
  done
fi

# 5. The AppImage itself.
if [ -n "$APPIMAGE_FILE" ] && [ "$KEEP_APPIMAGE" -eq 0 ]; then
  if [ -f "$APPIMAGE_FILE" ]; then
    if inside_home "$APPIMAGE_FILE"; then
      remove "$APPIMAGE_FILE"
    else
      echo "note: the AppImage is outside your home, so it was kept: $APPIMAGE_FILE"
    fi
  fi
elif [ -n "$APPIMAGE_FILE" ]; then
  echo "kept: $APPIMAGE_FILE"
fi

# 5b. With --purge, the local AI runtime and models too. Sized first, because
#     "a few gigabytes" is the number a user wants before answering.
if [ "$PURGE" -eq 1 ] && [ -d "$CACHE_DIR/local-ai" ]; then
  size="$(du -sh "$CACHE_DIR/local-ai" 2>/dev/null | cut -f1)"
  echo "local AI (model server and downloaded models): $CACHE_DIR/local-ai (${size:-?})"
  remove "$CACHE_DIR/local-ai"
  rmdir "$CACHE_DIR" 2>/dev/null || true
fi

# 6. The .deb, which belongs to the package manager. Removing its files by hand
#    would leave dpkg believing the package is still installed.
if command -v dpkg-query >/dev/null 2>&1 && dpkg-query -W -f='${Status}' openmila 2>/dev/null | grep -q "install ok installed"; then
  echo ""
  echo "OpenMila is also installed from the .deb. Finish with:"
  echo "  sudo apt remove openmila"
  echo "That removes the program and leaves your recordings and settings alone."
fi

# 7. Regenerable data, on request.
if [ "$PURGE_MODELS" -eq 1 ] || [ "$PURGE" -eq 1 ]; then
  if confirm "Delete the downloaded models and diarization packages in $DATA_DIR?"; then
    remove "$DATA_DIR/Models"
    remove "$DATA_DIR/torch-site-packages"
  else
    echo "kept: the downloaded models"
  fi
fi

# 8. Everything else, on request, and only after a typed confirmation. Settings
#    and logs go first because they are cheap to lose; the recordings are asked
#    for separately, because they are not.
if [ "$PURGE" -eq 1 ]; then
  for plist in "$CONFIG_HOME"/openmila*.plist "$CONFIG_HOME/$ID"*.plist; do
    [ -e "$plist" ] || continue
    remove "$plist"
  done
  remove "$LOG_DIR"
  if confirm_typed; then
    remove "$DATA_DIR"
  else
    echo "kept: $DATA_DIR (recordings and transcripts)"
  fi
fi

if [ "$DRY" -eq 0 ]; then
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q "$DATA_HOME/applications" 2>/dev/null || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t "$ICON_ROOT" 2>/dev/null || true
  fi
  if command -v update-mime-database >/dev/null 2>&1; then
    update-mime-database "$DATA_HOME/mime" 2>/dev/null || true
  fi
fi

echo ""
# "purged" is claimed only when the data directory really went, so a --purge
# that was asked in a script (no terminal, so nothing to answer) does not report
# a deletion it correctly refused to perform.
if [ "$PURGE" -eq 1 ] && [ ! -d "$DATA_DIR" ]; then
  echo "OpenMila and the data you asked to purge are gone."
else
  echo "OpenMila is gone. Kept, on purpose:"
  if [ -d "$DATA_DIR" ]; then echo "  $DATA_DIR    recordings, transcripts, models"; fi
  if [ -d "$LOG_DIR" ]; then echo "  $LOG_DIR    logs"; fi
  echo "  $CONFIG_HOME    settings"
  echo "Reinstalling picks them all up again. To delete them: openmila-uninstall --purge"
fi
