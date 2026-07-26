#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION_LINE="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
BUILD_NAME="${VERSION_LINE%%+*}"
BUILD_NUMBER="${VERSION_LINE#*+}"

if [[ "$BUILD_NAME" == "$VERSION_LINE" ]]; then
  BUILD_NUMBER="1"
fi

flutter pub get
flutter build macos \
  --release \
  --build-name="$BUILD_NAME" \
  --build-number="$BUILD_NUMBER"

"$ROOT_DIR/scripts/package_macos_dmg.sh" \
  "$ROOT_DIR/build/macos/Build/Products/Release/Perfect Collage.app" \
  "$BUILD_NAME" \
  "$ROOT_DIR/dist"
