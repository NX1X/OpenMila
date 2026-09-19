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

OpenMila is built with [Dagger](https://dagger.io). The Dagger module wraps
these same stages; it is pending a Dagger release whose SDK install works (the
1.0.0-beta.11 CLI fails `dagger sdk install` for both Go and Python with
`repository does not contain ref "v1@v1"`).
