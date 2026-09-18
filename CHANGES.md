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
| `.gitignore` | appended an OpenMila block | Ignore internal planning notes and local tooling files. |
