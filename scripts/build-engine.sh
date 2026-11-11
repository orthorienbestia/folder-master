#!/bin/bash
set -euo pipefail
if [ -n "${PROJECT_DIR:-}" ]; then
    TASK_ROOT="$(cd "$PROJECT_DIR/.." && pwd)"
else
    TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=14.0
CONFIG="${CONFIGURATION:-Debug}"
OUTPUT="$TASK_ROOT/build/rust/$CONFIG"
mkdir -p "$OUTPUT"
LIBRARIES=()
for ARCH in ${ARCHS:-$(uname -m)}; do
    case "$ARCH" in
        arm64) RUST_TARGET=aarch64-apple-darwin ;;
        x86_64) RUST_TARGET=x86_64-apple-darwin ;;
        *) echo "Unsupported macOS architecture: $ARCH" >&2; exit 1 ;;
    esac
    FLAGS=(--locked --offline)
    PROFILE=debug
    if [ "$CONFIG" = Release ]; then FLAGS+=(--release); PROFILE=release; fi
    cargo build --lib --manifest-path "$TASK_ROOT/Cargo.toml" --target "$RUST_TARGET" "${FLAGS[@]}"
    LIBRARIES+=("$TASK_ROOT/target/$RUST_TARGET/$PROFILE/libfolder_master_engine.a")
done
/usr/bin/lipo -create "${LIBRARIES[@]}" -output "$OUTPUT/libfolder_master_engine.a"
