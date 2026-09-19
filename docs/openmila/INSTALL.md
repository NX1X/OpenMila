# Installing and using OpenMila

## Linux

Tested on Ubuntu 26.04 (GNOME, Wayland and X11). Other current desktops with
GTK 4 should work.

1. Download `OpenMila-<version>-x86_64.AppImage` from the
   [releases page](https://github.com/NX1X/OpenMila/releases) and check it
   against the `.sha256` file next to it:
   ```bash
   sha256sum -c OpenMila-<version>-x86_64.AppImage.sha256
   ```
2. Make it executable and run it:
   ```bash
   chmod +x OpenMila-<version>-x86_64.AppImage
   ./OpenMila-<version>-x86_64.AppImage
   ```
   If it complains about FUSE, run it with `--appimage-extract-and-run`, or
   install `libfuse2t64`.

**Needed from the system:** GTK 4, PipeWire or PulseAudio. **Optional:**
`ffmpeg` (compact `.m4a` recordings, the remote transcription backend, and
importing audio that is not WAV), `wl-clipboard` or `xclip` (dictation to the
clipboard), `wtype` (Wayland) or `xdotool` (X11) for dictation that pastes by
itself.

### First run

The Whisper models are large and are not bundled. Open **Settings > Models**
and download the one you need: OpenAI large-v3-turbo for English and other
languages (1.6 GB), ivrit.ai large-v3 for Hebrew (3 GB). Each download is
checked against a pinned SHA-256 before it is used.

### Where things are

| What | Where |
|---|---|
| Recordings, transcripts, models, settings sidecars | `~/.local/share/Mila/` |
| Logs | `~/.local/state/openmila/logs/openmila.log` |
| Settings | `~/.config/` (managed by the app) |

The data folder is named `Mila` on purpose: the MCP helper and other shared
code look for it by that name.

### Dictation hotkeys

Ctrl+Alt+2 dictates English and Ctrl+Alt+3 Hebrew (change them in
**Settings > General**). Global hotkeys work on X11 sessions. On Wayland the
desktop owns global shortcuts, so use the Dictate buttons on the Home screen;
the text lands on the clipboard and a notification tells you to press Ctrl+V,
unless `wtype` is installed.

### Recording other applications

Choose **System audio** or **Meeting (mic + system)** as the source. On Linux
this records everything the machine plays, through the output's monitor
source. Recording a single application is planned.

## Windows

Not yet released. Windows 11 support is being built next.

## macOS

Use the original: [Mila](https://github.com/island-io/mila).

## Reporting a problem

**Settings > General > Export diagnostic report** writes a zip with system
information, your settings (credentials redacted, prompts reduced to their
length), the shape of your recordings (no titles or paths) and the log files.
Attach it to an [issue](https://github.com/NX1X/OpenMila/issues).
