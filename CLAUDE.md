# OpenMila

OpenMila is an independent community port of Mila (github.com/island-io/mila,
Apache-2.0, macOS only) to Linux and Windows. This file is what any session,
local or cloud, must know before touching the repository. The private working
notes (memory, plans, backlog, test script) live in `NX1X/OpenMila-internal`;
clone it beside this repository when you have access, and read its CLAUDE.md.

## Rules that hold everywhere

1. No em dashes or en dashes, in any file, commit message or reply. Hyphens.
2. No AI attribution anywhere: no `Co-Authored-By` lines, no "generated with".
   Commit messages describe the change only.
3. No products, images, libraries or models from China, Russia, Iran or North
   Korea. Local AI offers Western, open-licensed models only; a test enforces
   the catalogue (`Port/Tests/LocalAITests`).
4. Pin by digest, taken from the source. Never write a digest from memory.
5. Never claim more than `docs/port/PARITY.md` proves. Windows rows stay
   "written" until a human has run them.
6. Clear writing: short sentences, active voice, one term per concept.

## How the port is built

- `Package.swift` at the root builds Linux and Windows; it `#error`s on macOS.
  Upstream's own build stays `project.yml` and Xcode.
- Upstream files under `Mila/`, `Packages/`, `MilaTests/` are reused as they
  are. The port edits one only for a hygiene change that is also sent
  upstream, and every such edit is a row in `CHANGES.md`.
- Shim modules named `Combine`, `OSLog`, `os`, `CryptoKit`, `Accelerate`,
  `SwiftUI` let upstream imports compile unchanged. A shim's name makes
  `canImport(<name>)` true package-wide. Never shim `Darwin`.
- Port code lives under `Port/`: `PlatformKit` (protocols), `LinuxPlatform`,
  `WindowsPlatform`, `App` (SwiftCrossUI, its own package in `Port/App`),
  `CoreTwins`, `LocalAI`, `MCP`, `CLI`, `SelfTest`, `Tests`.
- Build: `bash scripts/port/setup-linux.sh` once, then
  `source scripts/port/env.sh && swift build $OPENMILA_SWIFT_FLAGS`. The app
  package needs `--build-system native -j 3` (the default build system
  ignores platform conditions on dependencies).
- Windows is built, tested, started and photographed on GitHub CI only; the
  screenshots land on the `ci-screenshots` branch.

## Upstream sync

Upstream is `island-io/mila`, tracked in `UPSTREAM_VERSION`. Sync on stable
tags: merge, keep this `CLAUDE.md` and drop `.claude/` from the merge, update
`UPSTREAM_VERSION`, re-port every changed view under `Port/App/Sources/Views`,
re-run the parity audit, release as `<upstream>+port.0`.

## Release

Notes first: `RELEASE_NOTES/v<version>.md` must exist or the release stops.
Version lives in `Port/App/Sources/AppModel.swift` (`AppIdentity.version`).
Tag `v<version>`; the release workflow builds, checks the app starts on a
clean Windows runner, and drafts the release. Publish only after verifying.
