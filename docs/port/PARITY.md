<!-- Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0. -->
# Feature parity with Mila

OpenMila copies Mila's features rather than inventing new ones, so this file is
the list of what Mila does and where each port stands. It is measured against
upstream **v1.9.5-beta.2** (see `UPSTREAM_VERSION`); OpenMila's own version is
`1.9.5+port.0-dev`.

Status values, and what each one claims:

| Status | Meaning |
|---|---|
| **done** | Implemented and exercised on that OS, by a test, the CI pipeline, the headless self-test, or a run of the app. |
| **partial** | Works, with a stated limitation. |
| **written** | Code exists but nothing has run it yet on that OS. Every Windows row is at best this until the Windows CI job is green. |
| **planned** | Not started. |
| **n/a** | Apple-only mechanism with no equivalent, or nothing to do. |

Linux is the development platform (Ubuntu 26.04, GNOME/Wayland, no GPU), so its
evidence is direct. Windows is built and tested on a `windows-2025` runner in
CI - core, CLI, MCP helper, the port's tests, the WinUI app and the portable
zip all pass there - but no Windows row is **done**, because nobody has run any
of it on a Windows desktop yet.

## Recording and capture

| # | Feature | Linux | Windows |
|---|---|---|---|
| 1 | Microphone recording, device picker, pinned input, live input level | done - miniaudio, `openmila-cli devices` and `record` | written - same capture code, WASAPI backend |
| 2 | System audio from one chosen app | done - PipeWire links a capture stream to the chosen application's output (`pw-record --target`), with whole-system monitors still offered; verified with `openmila-cli app-audio` (3.07 s captured from one player, peak 0.78) | partial - whole-system loopback; WASAPI process loopback not done |
| 3 | Meeting mode: mic + app audio mixed to one mono 16 kHz WAV | done - `Port/Recording/RecordingSession.swift`, `RecordingTests` | written |
| 4 | Independent mic / app-audio toggles | done | written |
| 5 | Pause and resume with the paused span absent from audio and timer | done - `RecordingTests` | written |
| 6 | Folder and meeting name chosen at record start | done | written |
| 7 | Adaptive gain control for quiet mics | done - upstream's `AdaptiveGainController`, vDSP calls behind the `Accelerate` shim | written |
| 8 | Mic stall watchdog and app-audio restart with backoff | partial - upstream's `CaptureStallDetector` logic is in the core; device-change events from miniaudio are not wired to it | partial - same |
| 9 | Mic bring-up timeout with an error that names the device | done | written |
| 10 | Refuse to transcribe an empty capture, duration read from the file | done | written |
| 11 | AAC `.m4a` recordings | partial - `AudioCompressor` twin shells out to ffmpeg when present, WAV otherwise | planned - Media Foundation encoder not written |
| 12 | Configurable recordings directory | done - plain paths, no security-scoped bookmarks | written |
| 13 | Storage cap, respected by dictation | done - upstream code, unchanged | written |
| 14 | Auto-discard accidental clips | done - upstream code, unchanged | written |
| 15 | Sleep and screen-lock guard while recording | done - `gnome-session-inhibit`, `systemd-inhibit` fallback | written - `SetThreadExecutionState` |
| 16 | Crash-recovered WAV header repair | done - upstream `WAVHeaderRepair`, `WAVHeaderRepairTests` runs off macOS | written |
| 17 | Meeting detection (Zoom, Teams, Meet) with prompts to start and stop | partial - process names from `/proc`; window titles are unavailable on Wayland, so Meet in a browser is not detected | written - process names via `CreateToolhelp32Snapshot`; window titles not wired |
| 18 | Live level meters and elapsed clock without re-rendering the app | done - `RecordingMeters`, observed by the leaf view only | written |

## Transcription

| # | Feature | Linux | Windows |
|---|---|---|---|
| 19 | On-device whisper.cpp, ivrit.ai large-v3 (Hebrew) and large-v3-turbo (English) | partial - runs, but on the CPU only: no GPU backend is built and `use_gpu` is off without Metal. Mila uses the Mac's GPU, so this is the port's largest performance gap. See [HARDWARE.md](HARDWARE.md) | partial - same, CPU only |
| 20 | CoreML / ANE encoder and its banner | n/a - no ANE; `.mlmodelc` downloads skipped | n/a |
| 21 | First-launch model download with progress and SHA-256 verification | done - verified by downloading both models | written |
| 22 | Model deletion frees the whole install and keeps the choice sane | done - upstream `ModelManager` | written |
| 23 | Recording language Hebrew or English, model routed per language | done | written |
| 24 | Remote transcription on any OpenAI-compatible endpoint | done - upstream code with the port's `SecretStore`; exercised against `scripts/mock-openai-transcription-server.py` | written |
| 25 | Neural VAD (Silero) and hallucination reduction | done - `TranscriptionCore` as-is, weights bundled | written |
| 26 | Live transcription while recording, mic and app audio | done | written |
| 27 | Live transcript editing, copy, mid-recording SRT export | done - `Port/App/Sources/Views` | written - the app builds on Windows with the WinUI backend (CI packages a zip); nothing has run it |
| 28 | Hardware gate for Live AI on weak machines | done - `SystemCapabilities` twin reads RAM and `activeProcessorCount` | written |
| 29 | Transcription queue with no stuck items after relaunch | done - upstream `TranscriptionService` | written |
| 30 | Re-transcribe a recording, speaker names re-attached | done | written |
| 31 | Import and transcribe existing audio files | done - `FileTranscriber` twin; watched-folder import verified word for word | written |
| 32 | `audio_ctx` speed-up and beam search 5 | done - `TranscriptionCore` unchanged | written |

## Speakers

| # | Feature | Linux | Windows |
|---|---|---|---|
| 33 | Speaker diarization with pyannote, bundled Python runtime, torch on first enable | done - `diarization/build-bundle-linux.sh`, proven by `openmila-selftest diarize` (torch 2.2.2 installed at runtime, turns returned) | written - `build-bundle-windows.ps1` has never been run |
| 34 | Live speaker labels during recording | done - upstream `LiveSpeakerDiarizer` | written |
| 35 | A colour per speaker | done - port theme palette | written - the app builds on Windows with the WinUI backend (CI packages a zip); nothing has run it |
| 36 | Speaker directory: name, rename, merge, un-name, naming mid-recording | done | written - the app builds on Windows with the WinUI backend (CI packages a zip); nothing has run it |
| 37 | Cross-recording voice recognition, opt-in, deletable | done - upstream `OfflineVoiceEmbedder`, `SpeakerProfileStore` | written |
| 38 | Diarization toggle mid-recording takes effect immediately | done | written |

## Dictation

| # | Feature | Linux | Windows |
|---|---|---|---|
| 39 | Global hotkeys for English and Hebrew, configurable, conflict-checked | partial - X11 `XGrabKey`; the XDG `GlobalShortcuts` portal path (needed on Wayland) is not written | written - `RegisterHotKey` on a dedicated message thread |
| 40 | Dictation overlay pill with live text, level and busy state | done - app window; no layer-shell, so it is an ordinary always-on-top window | written - the app builds on Windows with the WinUI backend (CI packages a zip); nothing has run it |
| 41 | Paste at the cursor into the previous app, with clipboard fallback | partial - `wl-copy`/`xclip` plus `wtype`/`xdotool`; no `RemoteDesktop` portal path, so a bare Wayland session falls back to the clipboard | written - clipboard plus `SendInput` Ctrl+V |
| 42 | Dictations saved under History | done | written |

## AI features

| # | Feature | Linux | Windows |
|---|---|---|---|
| 43 | Providers: Claude, Cursor, Gemini CLIs and any OpenAI-compatible endpoint | done - real `claude` CLI produced a summary in 8 s | written - `.cmd` shims run through `cmd /c` |
| 44 | Managed Claude install with checksum and signature checks | partial - `linux-x64` manifest key and checksum verified; the signature check is the port's `SignatureVerifier`, which fails closed rather than verifying a signature | partial - `win32-x64` key, Authenticode verified with the signer's name checked; browser sign-in needs a real terminal until a ConPTY path replaces the POSIX pseudo-terminal |
| 45 | Suggested recording names | done | written |
| 46 | Automatic summary after each recording, backfill, regenerate, `.summary.txt` | done | written |
| 47 | Send to LLM with a custom prompt | done | written |
| 48 | Live AI rolling summary and action items with a per-recording context box | done | written - the app builds on Windows with the WinUI backend (CI packages a zip); nothing has run it |
| 49 | AI output language, per-feature prompts with an undo stack | done | written - the app builds on Windows with the WinUI backend (CI packages a zip); nothing has run it |
| 50 | Every CLI invocation logged with credentials redacted | done - `OpenMilaLogging` redacts unless `OPENMILA_LOG_PRIVATE=1` | written |

## Library and UI

| # | Feature | Linux | Windows |
|---|---|---|---|
| 51 | Sidebar: Home, All Transcriptions, folders with drag-and-drop, Dictations, watched folders, Recently Deleted | done - SwiftCrossUI + GTK4 | written - the app builds on Windows with the WinUI backend (CI packages a zip); nothing has run it |
| 52 | Detail view: playback, click to seek, 0.5x-2x speed, transcript follows playback | done - speed goes through a WSOLA time stretcher, so pitch is preserved (`StretchTests`); the stretched audio also transcribes to the same words at 0.75x and 1.5x, which is the intelligibility check a frequency test cannot give | written - the app builds on Windows with the WinUI backend (CI packages a zip); nothing has run it |
| 53 | Post-recording popup and rename sheet with summary and action items | done | written - the app builds on Windows with the WinUI backend (CI packages a zip); nothing has run it |
| 54 | Right-click context menu on recordings | done - GTK `GtkPopover` via a button-3 gesture | written - the app builds on Windows with the WinUI backend (CI packages a zip); nothing has run it |
| 55 | Copy and share transcript with speaker labels, SRT export, timestamps | done | written - core only |
| 56 | Hebrew RTL rendering per section | done - Pango handles bidi; direction decided per block by upstream's `HebrewDetection` | written - the app builds on Windows with the WinUI backend (CI packages a zip); nothing has run it |
| 57 | Hide recents toggle | done | written - the app builds on Windows with the WinUI backend (CI packages a zip); nothing has run it |
| 58 | Settings with all nine sections | done | written - the app builds on Windows with the WinUI backend (CI packages a zip); nothing has run it |
| 59 | "What's New" before an update | done - notes from the GitHub release body | written - the app builds on Windows with the WinUI backend (CI packages a zip); nothing has run it |
| 60 | Main menu commands and keyboard shortcuts | partial - the app's own shortcuts; no menu bar on GNOME | written - the app builds on Windows with the WinUI backend (CI packages a zip); nothing has run it |
| 61 | Diagnostic report export, credentials redacted, logs attached | done - `DiagnosticSnapshotProvider` twin over the port's own log files | written |
| 62 | Sidebar material chrome | partial - layered translucent surfaces approximate `.regularMaterial`; no blur | written - the app builds on Windows with the WinUI backend (CI packages a zip); nothing has run it |

## Integrations

| # | Feature | Linux | Windows |
|---|---|---|---|
| 63 | iPhone Voice Memos sync | done as watched folders - the same start-date and destination rules over any synced directory (iCloud discovery is macOS-only); inotify watcher, per-folder toggles | written - `ReadDirectoryChangesW` |
| 64 | `.milaconfig` one-click team setup | partial - in-app import works; no `.desktop` MIME association yet | partial - the app reads a path from argv; no file association yet |
| 65 | Obsidian export and vault git sync | done - `git` from PATH | written |
| 66 | MCP server with the consent gate | done - `openmila-mcp` through Claude Code: refused with consent off, listed recordings with it on | written - builds and ships in the Windows zip; nothing has run it there |
| 67 | Self-hosted server docs | done - `docs/self-hosted-server`, `docs/openmila/REMOTE_SERVER.md` | done - same docs |

## Updates, permissions, system

| # | Feature | Linux | Windows |
|---|---|---|---|
| 68 | Auto-update with a beta channel and a pre-release guard | done for the AppImage - the check, the beta channel and the pre-release guard, plus an install step that verifies the published SHA-256 and replaces the running AppImage (`SelfUpdateTests`); a `.deb` install is sent to the release page, since that belongs to the package manager | partial - the check works; the zip has no self-install |
| 69 | Permission prompts for microphone, screen recording, accessibility | n/a - no per-app permission gates; PipeWire and portal dialogs appear where the session requires them | n/a - the microphone privacy setting is the OS's own |
| 70 | Keychain storage for API keys | done - the desktop keyring through libsecret (GNOME Keyring, KWallet, KeePassXC), with 0600 files where no Secret Service answers (`SecretServiceStoreTests`) | written - DPAPI |
| 71 | Privacy-safe logging | done | written |
| 72 | Stable code signing so permissions survive updates | n/a | n/a |

## Per-upstream-release tracking

OpenMila is measured against one upstream tag at a time, not per release, so
this table records which upstream release the port currently matches and where
the archived reference build came from.

| Upstream tag | Date | Ported | Note |
|---|---|---|---|
| [v1.9.5-beta.2](https://github.com/island-io/mila/releases/tag/v1.9.5-beta.2) | 2026-09-17 | in progress | The version the port tracks. Every row above is measured against it. |
| [v1.9.4](https://github.com/island-io/mila/releases/tag/v1.9.4) | 2026-09-10 | in progress | Latest upstream stable; the archived build used for side-by-side comparison. |
| Earlier releases (v1.8.8 and up) | 2026-06-13 onwards | historical | Their features are folded into the tables above; upstream's own release notes are archived alongside the builds. |

## Rules for this file

- A row moves to **done** only with evidence on that OS. "It compiles" is not
  evidence.
- A feature that lands on one OS and not the other stays visible here rather
  than being quietly dropped.
- Update this file in the same change that moves a row, and re-measure it on
  every upstream sync.
