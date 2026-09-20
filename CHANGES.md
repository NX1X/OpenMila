# Changes to upstream files

OpenMila is a modified version of [Mila](https://github.com/island-io/mila)
(Apache-2.0). Section 4(b) of the licence requires modified files to say so.
Every upstream file the port edits is listed here and carries a one-line
notice at its top. New files under `Port/`, `scripts/port/`, and the root
`Package.swift` are OpenMila's own and are not listed.

The port's rule is to leave upstream files untouched and build around them, so
this list is meant to stay short. Each entry is also a candidate for an
upstream pull request, which would remove it from this list.

| File | Change | Why |
|---|---|---|
| `Mila/Transcription/ModelManager.swift` | `import os.log` -> `import os` | Swift modules cannot have submodules, so `os.log` cannot be provided off macOS. `import os` exposes the same `Logger` on macOS and resolves to the port's shim elsewhere. No behaviour change. |
| `Mila/Actions/ClaudeBinaryVerification.swift` | `import Security` and `SecurityFrameworkSignatureVerifier` wrapped in `#if canImport(Security)` | The Apple code-signing check cannot compile without the Security framework. Everything else in the file (errors, checksum verification, the verifier protocol) is portable and needed. Off macOS the port supplies a verifier of the same name that fails closed. No behaviour change on macOS. |
| `Packages/TranscriptionCore/Sources/TranscriptionCore/WhisperEngine.swift`, `SileroVAD.swift` | `#if canImport(os)` -> `#if canImport(os.log)` | The files import `os.log`, so that is the module to test for. With the port's `os` shim on the search path the looser test passed and the import then failed. No behaviour change on macOS. |
| `Mila/Actions/ClaudeManagedInstall.swift` | `platformKey` and `isPlausiblePlatform` gain `#if os(Linux)` / `#if os(Windows)` branches returning Anthropic's `linux-x64`, `linux-arm64` and `win32-x64` manifest keys | Without them the managed Claude install would ask for a macOS binary on other systems. The macOS branch is unchanged. |
| `README.md` | Replaced with OpenMila's own README | The README describes the product; the port's is not Mila's. Upstream's README is unchanged in Mila's repository. On upstream sync, keep ours and refresh the verbatim copy at `docs/upstream/MILA-README.md`. |
| `.github/dependabot.yml` | Removed | Renovate owns dependency updates for the port (`.github/renovate.json`); Dependabot stays on for vulnerability alerts only, which needs no config file. Upstream's file would open weekly PRs against upstream-owned workflows. |
| `Mila/Transcription/DiarizationBootstrap.swift` | `wheelURLs` gains `#if os(Linux)` / `#if os(Windows)` branches with the `linux_x86_64` and `win_amd64` CPU wheels of the same pinned torch version | The macOS wheels cannot install on other systems, so speaker diarization could never start. Versions and the install flow are unchanged; the macOS branch is upstream's. |
| `NOTICE` | OpenMila's paragraph appended below Mila's, which is unchanged | Apache-2.0 section 4(d) allows adding one's own notice alongside the original. |
| `CONTRIBUTING.md`, `SECURITY.md`, `THIRD_PARTY_NOTICES.md` | Replaced with OpenMila's | They describe how to contribute to and report issues in this project, and what its Linux and Windows packages contain. Mila's originals are kept verbatim in `docs/upstream/`. |
| `CODE_OF_CONDUCT.md` | Enforcement contact changed to this project's maintainer | Mila's maintainer is not responsible for conduct in this repository. |
| `.github/CODEOWNERS`, `.github/ISSUE_TEMPLATE/*`, `.github/pull_request_template.md` | Replaced with OpenMila's | Review ownership and issue fields for this repository. Mila's CODEOWNERS is kept in `docs/upstream/`. |
| `.gitignore` | appended an OpenMila block | Ignore internal planning notes and local tooling files. |
