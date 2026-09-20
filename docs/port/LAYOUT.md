# Repository layout

OpenMila is Mila plus a port layer. Two rules keep the upstream sync cheap:

1. **Upstream directories are never edited or moved.** `Mila/`, `Packages/`,
   `MilaMCP/`, `MilaTests/`, `MilaUITests/`, `docs/` (except `docs/port/` and
   `docs/upstream/`), `docker/`, `scripts/` (except `scripts/port/`),
   `RELEASE_NOTES/`, `project.yml`, `Makefile`, `bugbot-rules/`, `.cursor/`
   and upstream's workflows are Mila's, byte for byte. The few exceptions
   carry a one-line notice and are listed in `CHANGES.md`.
2. **Everything the port adds lives under `Port/`, `ci/`, `scripts/port/`,
   `docs/port/`, and the root `Package.swift`.**

The root `Package.swift` is the map. It compiles upstream's `Mila/` tree in
place as the `Mila` module, excluding the files bound to Apple frameworks, and
adds the port's replacements from `Port/CoreTwins` into the same module.
macOS builds keep using upstream's `project.yml`; this manifest refuses to
build on macOS.

| Path | Owner | What |
|---|---|---|
| `Mila/` | upstream | App logic, models, transcription, audio, views (views and Apple-bound files excluded from the Linux/Windows build) |
| `Packages/MilaKit`, `Packages/TranscriptionCore` | upstream | Cross-platform packages, used unchanged |
| `MilaMCP/` | upstream | The MCP helper's source, built as `openmila-mcp` |
| `Port/Shims/` | port | Modules named `Combine`, `OSLog`, `os`, `CryptoKit`, `Accelerate`, `SwiftUI` so upstream imports compile off macOS |
| `Port/CoreTwins/` | port | Replacements for excluded upstream files, compiled into the `Mila` module |
| `Port/PlatformKit/` | port | Protocols between the core and each OS |
| `Port/LinuxPlatform/`, `Port/WindowsPlatform/` | port | Per-OS implementations |
| `Port/AudioCapture/`, `Port/CMiniaudio/` | port | miniaudio capture and playback |
| `Port/Recording/` | port | Recording session twin and WAV writer |
| `Port/Updater/` | port | GitHub Releases update check |
| `Port/App/` | port | The SwiftCrossUI app, its own package, one view file per upstream view |
| `Port/CLI/` | port | `openmila-cli`, the headless harness |
| `Port/Tests/` | port | The port's tests plus the TestSupport twin for upstream's tests |
| `brand/` | port | The brand kit: mark, lockups, design tokens, and the renderer that produces every raster icon |
| `ci/` | port | Pipeline script and container image |
| `scripts/port/` | port | Developer environment helpers |
| `docs/upstream/` | port | Verbatim copy of Mila's README, refreshed on sync |

## Brand and icons

All of OpenMila's artwork lives in `brand/`, and none of it comes from Mila.
The rules for using it, the colour tokens and the one-paragraph explanation of
what the mark means are in [`brand/brand.md`](../../brand/brand.md).

- Sources: `mark.svg` (the mark), `mark-small.svg` (its 16px cut),
  `logo.svg`, `logo-stacked.svg`, `logo-mono.svg`.
- Tokens: `tokens.css` and `tokens.json`, the same colours and spacing the app
  uses in `Port/App/Sources/Theme/Theme.swift`, for the website to import.
- Generated and committed: `brand/icons/` (PNG at 16 to 512, `openmila.ico`,
  `favicon.ico`) and `brand/social-preview.png`.

Regenerate after changing any SVG, and commit what changes:

```bash
python3 brand/render-icons.py
```

The renderer is standard library only (no imaging package, nothing to install),
and packaging never runs it: the scripts copy the committed files.

Where each surface picks the artwork up:

| Surface | File | Wired in |
|---|---|---|
| Linux icon theme | `icons/openmila-<size>.png` installed as `io.github.nx1x.openmila.png` under every `hicolor/<size>x<size>/apps` | `packaging/appimage/build.sh`, `packaging/deb/build.sh` |
| AppImage and `.desktop` entry | the 256px file, and `Icon=io.github.nx1x.openmila` | `packaging/appimage/build.sh` |
| Windows zip | `openmila.ico` beside the binaries, and compiled into `openmila.exe` as a resource when `rc.exe` is on PATH | `packaging/windows/package.ps1` |
| Website | `icons/favicon.ico` and `icons/openmila-512.png` | the website repository |
| GitHub social preview | `social-preview.png` | repository settings, by hand |
| About screen | `openmila.png` beside the binaries (the 128px file, copied there by packaging) | `Port/App/Sources/Views/AboutView.swift` |
| Window icon | resolved by name from the icon theme on Linux, from the `.exe` resource on Windows | `Port/App/Sources/Native/Platform.swift` |

A build run straight from the source tree has no icon tree and no
`openmila.png` beside the binary, so the About screen leaves the mark out and
the window falls back to the desktop's default. Both come right in a packaged
build; to see them from a source build, copy `brand/icons/openmila-128.png`
next to the executable as `openmila.png`.

Build on Linux:

```bash
source scripts/port/env.sh
cd Port/App && swift build $OPENMILA_APP_FLAGS --product openmila
../../scripts/port/link-resources.sh .build/debug
.build/debug/openmila
```
