#!/usr/bin/env bash
# Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#
# Source this file to get a shell that can build OpenMila on Linux:
#   source scripts/port/env.sh && swift build $OPENMILA_SWIFT_FLAGS
#
# Swift 6.4's build system ignores CPATH / LIBRARY_PATH, so the whisper.cpp
# prefix has to be passed as explicit flags.
: "${OPENMILA_SWIFT_HOME:=$HOME/.local/swift-6.4.0}"
: "${OPENMILA_WHISPER_PREFIX:=$HOME/.local/whisper-9386f23}"

if [ ! -x "$OPENMILA_SWIFT_HOME/usr/bin/swift" ]; then
  echo "env.sh: no Swift toolchain at $OPENMILA_SWIFT_HOME" >&2
  return 1 2>/dev/null || exit 1
fi
if [ ! -f "$OPENMILA_WHISPER_PREFIX/include/whisper.h" ]; then
  echo "env.sh: no whisper.cpp install at $OPENMILA_WHISPER_PREFIX" >&2
  return 1 2>/dev/null || exit 1
fi

export PATH="$OPENMILA_SWIFT_HOME/usr/bin:$PATH"
export LD_LIBRARY_PATH="$OPENMILA_WHISPER_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export OPENMILA_SWIFT_FLAGS="-Xcc -I$OPENMILA_WHISPER_PREFIX/include -Xlinker -L$OPENMILA_WHISPER_PREFIX/lib"
# For the app package only (Port/App): classic build system, bounded parallelism.
export OPENMILA_APP_FLAGS="--build-system native -j 3 $OPENMILA_SWIFT_FLAGS"

# Link bundled resources beside the build products so Bundle.main finds them:
#   openmila-link-resources
openmila-link-resources() {
  "$(dirname "${BASH_SOURCE[0]}")/link-resources.sh" "$(swift build --show-bin-path $OPENMILA_SWIFT_FLAGS 2>/dev/null | tail -1)"
}
