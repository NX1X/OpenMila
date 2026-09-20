# OpenMila

OpenMila brings [Mila](https://github.com/island-io/mila), the local
transcription app for macOS, to **Linux desktop** and **Windows**. Same
features, same models, same on-device privacy: recording, dictation, Hebrew
and English transcription with whisper.cpp, speaker diarization, AI summaries,
and the MCP server for your AI tools. Nothing leaves your machine unless you
point it at a server of your own.

Website: [OpenMila.nx1xlab.dev](https://openmila.nx1xlab.dev)

> OpenMila is an independent community port of Mila for Linux and Windows.
> It is not affiliated with or endorsed by Island Technology, Inc.

**On a Mac, use the original:** [island-io/mila](https://github.com/island-io/mila).
OpenMila does not build for macOS and does not try to.

## Status

Early development, not yet released. Follow the
[releases page](https://github.com/NX1X/OpenMila/releases) for the first
Linux beta.

## Credits

Mila was created by [Uri Harduf](https://github.com/urisland) at
[Island](https://www.island.io/) and released under the Apache License 2.0
at [github.com/island-io/mila](https://github.com/island-io/mila). OpenMila reuses Mila's
transcription engine, data model and application logic unchanged wherever the
platform allows, and re-implements only what is tied to macOS. The list of
upstream files this port modifies is in [CHANGES.md](CHANGES.md). Mila's
own README, with its feature list, requirements and changelog, is kept
verbatim at [docs/upstream/MILA-README.md](docs/upstream/MILA-README.md)
and refreshed on every upstream sync.

OpenMila is built with [Dagger](https://dagger.io).

## Versioning

OpenMila follows Mila's releases. Each OpenMila version is a port of one Mila
version, named `<mila version>+port.<n>`: `1.9.5+port.1` is Mila 1.9.5, first
port build. Features, models and engine pins track upstream; the port adds
platform code, not features. The Mila version currently matched is in
[`UPSTREAM_VERSION`](UPSTREAM_VERSION).

## Documentation

- [Installing and using OpenMila](docs/openmila/INSTALL.md)
- [Using OpenMila with Claude (MCP)](docs/openmila/MCP.md)
- [Remote transcription](docs/openmila/REMOTE_SERVER.md): using your own
  server, with Mila's server guides and the few app-side differences
- [Contributing](CONTRIBUTING.md), [Security policy](SECURITY.md),
  [Repository layout](docs/port/LAYOUT.md)

## Building on Linux (developers)

Ubuntu 26.04, Swift 6.4.0, whisper.cpp from the pinned submodule. See
[`ci/README.md`](ci/README.md); `ci/run.sh all` builds and tests everything
the way CI does.

## Contact

The best way to reach the maintainer is this repository: open an
[issue](https://github.com/NX1X/OpenMila/issues) for bugs and requests, or a
[discussion](https://github.com/NX1X/OpenMila/discussions) for questions.
Security problems go through
[private vulnerability reporting](https://github.com/NX1X/OpenMila/security/advisories/new).
For anything else, the contact form and social links are at
[nx1xlab.dev/contact](https://nx1xlab.dev/contact).

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
