# Contributing to OpenMila

Thanks for your interest. OpenMila is Mila, the local transcription app for
macOS, ported to Linux and Windows. That shapes how contributions work.

## The one rule

OpenMila follows Mila. Features, models and engine versions come from
[Mila upstream](https://github.com/island-io/mila); OpenMila adds the
platform code that lets them run elsewhere. So:

- **Upstream directories are not edited or moved.** `Mila/`, `Packages/`,
  `MilaMCP/`, `MilaTests/` and the other directories listed in
  [docs/port/LAYOUT.md](docs/port/LAYOUT.md) are Mila's. A change there
  belongs in a pull request to Mila, not here. The rare exception is a
  minimal edit that makes a file compile off macOS; it gets a one-line notice
  in the file and a row in [CHANGES.md](CHANGES.md).
- **Port code lives under `Port/`, `ci/`, `scripts/port/`, `packaging/` and
  `docs/port/`.**
- **New features go to Mila first.** A feature OpenMila has and Mila does not
  is a fork, and forks are not the goal.
- **Both operating systems.** A change that works on Linux but not Windows
  (or the reverse) needs a tracking issue for the other side.

## Development setup (Linux)

Ubuntu 26.04 or similar, Swift 6.4.0, and the build dependencies listed in
[ci/Dockerfile](ci/Dockerfile).

```bash
git clone --recurse-submodules https://github.com/NX1X/OpenMila.git
cd OpenMila
ci/run.sh whisper                 # builds whisper.cpp at the pinned commit
source scripts/port/env.sh
swift build $OPENMILA_SWIFT_FLAGS # the core, CLI and MCP helper
cd Port/App && swift build $OPENMILA_APP_FLAGS --product openmila
```

`ci/run.sh all` builds and tests everything the way CI does. Run it before
opening a pull request.

## Pull requests

- Open an issue first and link it from the PR (`Closes #n`).
- Branch from `main`; keep each PR to one change and explain what and why.
- CI must be green. Tests that fail off macOS are listed by name in
  `ci/run.sh`; any other failure blocks the merge.
- Never commit secrets, tokens, or internal infrastructure details.

## Bugs

Use the issue templates. Attach the diagnostic report (Settings > General >
Export diagnostic report) or the log file it points to. For security
problems follow [SECURITY.md](SECURITY.md) instead.

## License

By contributing you agree that your contributions are licensed under the
[Apache License 2.0](LICENSE).
