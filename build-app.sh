#!/bin/bash
# Build and bundle ForensicKitDesktop as a proper macOS .app
# Usage: bash build-app.sh [--release]

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_MODE="${1:---debug}"

if [ "$BUILD_MODE" = "--release" ]; then
    CONFIG="release"
    BUILD_FLAG="-c release"
else
    CONFIG="debug"
    BUILD_FLAG=""
fi

APP_NAME="ForensicKit"
APP_DIR="$PROJECT_ROOT/.build/$CONFIG/$APP_NAME.app"

echo "==> Building ForensicKit ($CONFIG)..."
swift build $BUILD_FLAG --product forensic-kit-desktop

echo "==> Creating .app bundle at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Binary
BINARY="$PROJECT_ROOT/.build/$CONFIG/forensic-kit-desktop"
cp "$BINARY" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Info.plist
cp "$PROJECT_ROOT/Sources/ForensicKitDesktop/Info.plist" "$APP_DIR/Contents/"

echo "==> Bundle created: $APP_DIR"
echo "Run: open \"$APP_DIR\""
