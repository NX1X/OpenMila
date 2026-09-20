# OpenMila pipeline

One script, one environment, every caller:

- `ci/run.sh <stage>` is the pipeline: `whisper`, `packages`, `shims`, `core`,
  `cli`, `e2e`, or `all`. It runs unchanged on a developer machine, inside the
  container, and from GitHub Actions.
- `ci/Dockerfile` is the environment: Ubuntu 26.04 pinned by digest, Swift 6.4.0
  from swift.org with its signature checked against a pinned key fingerprint.

Run it the way CI does:

```bash
docker build -t openmila-ci:local -f ci/Dockerfile ci
docker run --rm -v "$PWD":/src:ro -v ~/.cache/whisper-models:/models:ro \
  -e OPENMILA_E2E_MODEL=/models/ggml-tiny.bin openmila-ci:local bash -c \
  'mkdir -p /work/repo && cd /src && tar --exclude=./.build -cf - . | tar -xf - -C /work/repo && cd /work/repo && ci/run.sh all'
```

The `core` stage runs upstream's own unit tests. Tests known to fail off macOS
are listed by name in `run.sh`; any other failure fails the build.

## Dagger

OpenMila's pipeline is a [Dagger](https://dagger.io) module (`ci/dagger`,
`dagger.json` at the root). It builds `ci/Dockerfile` and runs the stages of
`ci/run.sh` inside it, with build output, the whisper.cpp build and SwiftPM
caches kept in cache volumes.

```bash
dagger functions                        # list them
dagger call check                       # every stage, as CI runs it
dagger call stage --name=core           # one stage
dagger call app-image export --path=dist   # the Linux AppImage
```

Dagger v0.21.9 or newer is needed. GitHub Actions installs the same CLI version,
checksum-pinned, and runs `dagger call check`.
