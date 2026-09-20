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
| `ci/` | port | Pipeline script and container image |
| `scripts/port/` | port | Developer environment helpers |
| `docs/upstream/` | port | Verbatim copy of Mila's README, refreshed on sync |

Build on Linux:

```bash
source scripts/port/env.sh
cd Port/App && swift build $OPENMILA_APP_FLAGS --product openmila
../../scripts/port/link-resources.sh .build/debug
.build/debug/openmila
```
