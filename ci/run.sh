#!/usr/bin/env bash
# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# The Linux pipeline, one stage per function. Runs the same way on a developer
# machine, inside ci/Dockerfile, and from CI. Usage:
#   ci/run.sh all | whisper | packages | shims | core | cli | e2e
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

WHISPER_SRC="$ROOT/Packages/TranscriptionCore/vendor/whisper.cpp"
WHISPER_PIN="$(tr -d '[:space:]' < .github/whisper-cpp-pin.txt)"
export OPENMILA_WHISPER_PREFIX="${OPENMILA_WHISPER_PREFIX:-$HOME/.local/whisper-${WHISPER_PIN:0:7}}"
MODEL="${OPENMILA_E2E_MODEL:-$HOME/.cache/whisper-models/ggml-tiny.bin}"

if ! command -v swift >/dev/null 2>&1; then
  export PATH="${OPENMILA_SWIFT_HOME:-$HOME/.local/swift-6.4.0}/usr/bin:$PATH"
fi
export LD_LIBRARY_PATH="$OPENMILA_WHISPER_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
FLAGS=(-Xcc "-I$OPENMILA_WHISPER_PREFIX/include" -Xlinker "-L$OPENMILA_WHISPER_PREFIX/lib")
# The app package needs the classic build system: Swift 6.4's default one
# compiles every target of SwiftCrossUI, including Windows-only ones, and
# fails on Linux. -j 3 keeps the app's dependency builds inside 14 GB.
APP_FLAGS=(--build-system native -j 3 "${FLAGS[@]}")

log() { printf '\n==> %s\n' "$1"; }

# Swift 6.4's build tool occasionally crashes while planning. That is not a
# test result, so retry it; a real failure fails every attempt.
retry() {
  local attempt
  for attempt in 1 2 3; do
    if "$@"; then return 0; fi
    echo "attempt $attempt failed" >&2
  done
  return 1
}

stage_whisper() {
  log "whisper.cpp at the pinned commit"
  local actual
  actual="$(git -C "$WHISPER_SRC" rev-parse HEAD)"
  if [ "$actual" != "$WHISPER_PIN" ]; then
    echo "whisper.cpp is at $actual, expected the pin $WHISPER_PIN" >&2
    exit 1
  fi
  if [ -f "$OPENMILA_WHISPER_PREFIX/lib/libwhisper.so" ]; then
    echo "already built at $OPENMILA_WHISPER_PREFIX"
    return
  fi
  cmake -S "$WHISPER_SRC" -B "$WHISPER_SRC/build-linux" -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF \
    -DGGML_NATIVE=OFF -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ \
    -DCMAKE_INSTALL_PREFIX="$OPENMILA_WHISPER_PREFIX" >/dev/null
  cmake --build "$WHISPER_SRC/build-linux" -j"$(nproc)" >/dev/null
  cmake --install "$WHISPER_SRC/build-linux" >/dev/null
}

stage_packages() {
  log "upstream packages: MilaKit, TranscriptionCore"
  (cd Packages/MilaKit && retry swift test)
  (cd Packages/TranscriptionCore && retry swift test "${FLAGS[@]}")
}

stage_shims() {
  log "shim modules"
  retry swift test "${FLAGS[@]}" --filter '^ShimTests\.'
}

# Upstream tests that fail off macOS for reasons recorded in
# docs-internal/status. Listed by name so any OTHER failure fails the build.
KNOWN_FAILURES=(
  "LLMRunnerTests.test_diagnose_captures_command_stdout_and_success"
  "LLMRunnerTests.test_run_claude_unchanged_resolvesExecutableAndSpawns"
  "LLMRunnerTests.test_runner_passes_prompt_in_argv_and_closes_stdin"
  "ObsidianVaultSettingsTests.test_isContained_agrees_for_existing_and_missing_destinations"
  "SpeakerDiarizerCancelTests.test_cancelling_runPython_terminates_the_subprocess_promptly"
)

stage_core() {
  log "upstream core: build, then upstream's own unit tests"
  retry swift build --build-tests "${FLAGS[@]}"
  scripts/port/link-resources.sh "$(swift build --show-bin-path "${FLAGS[@]}" 2>/dev/null | tail -1)"
  local out
  out="$(mktemp)"
  swift test --skip-build "${FLAGS[@]}" --filter '^MilaTests\.' > "$out" 2>&1 || true
  grep -E "Executed [0-9]+ tests" "$out" | tail -1
  local failed unexpected=0
  failed="$(grep -E "^Test Case '.*' failed" "$out" | sed -E "s/^Test Case '([^']+)'.*/\1/" | sort -u)"
  if ! grep -qE "Executed [0-9]+ tests" "$out"; then
    echo "the test run did not complete" >&2; tail -20 "$out" >&2; exit 1
  fi
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    if printf '%s\n' "${KNOWN_FAILURES[@]}" | grep -qxF "$name"; then
      echo "known failure: $name"
    else
      echo "UNEXPECTED FAILURE: $name" >&2
      unexpected=1
    fi
  done <<< "$failed"
  rm -f "$out"
  [ "$unexpected" -eq 0 ]
}

stage_port() {
  log "port modules: recording session, Linux platform services"
  retry swift test "${FLAGS[@]}" --filter '^(RecordingTests|LinuxPlatformTests)\.'
}

stage_cli() {
  log "openmila-cli, openmila-mcp and the openmila app build"
  retry swift build --product openmila-cli "${FLAGS[@]}"
  retry swift build --product openmila-mcp "${FLAGS[@]}"
  (cd Port/App && retry swift build --product openmila "${APP_FLAGS[@]}")
}

stage_e2e() {
  log "end-to-end transcription on the English and Hebrew fixtures"
  if [ ! -f "$MODEL" ]; then
    echo "no model at $MODEL; set OPENMILA_E2E_MODEL. Skipping." >&2
    return 0
  fi
  (cd Packages/TranscriptionCore && retry swift run "${FLAGS[@]}" whisper-e2e \
      --model "$MODEL" --fixtures Fixtures --max-wer 0.3)
}

case "${1:-all}" in
  whisper) stage_whisper ;;
  packages) stage_whisper; stage_packages ;;
  shims) stage_whisper; stage_shims ;;
  core) stage_whisper; stage_core ;;
  port) stage_whisper; stage_port ;;
  cli) stage_whisper; stage_cli ;;
  e2e) stage_whisper; stage_e2e ;;
  all) stage_whisper; stage_packages; stage_shims; stage_core; stage_port; stage_cli; stage_e2e ;;
  *) echo "usage: ci/run.sh all|whisper|packages|shims|core|port|cli|e2e" >&2; exit 2 ;;
esac
log "done: ${1:-all}"
