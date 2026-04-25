#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Hex Fix"
EXECUTABLE_NAME="HexFix"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE="${CLANG_MODULE_CACHE_PATH:-/tmp/hex-fix-module-cache}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" swiftc \
    "$ROOT_DIR/main.swift" \
    "$ROOT_DIR"/App/*.swift \
    "$ROOT_DIR"/Domain/*.swift \
    "$ROOT_DIR"/UseCases/*.swift \
    "$ROOT_DIR"/Adapters/*.swift \
    -o "$MACOS_DIR/$EXECUTABLE_NAME"

chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"
codesign --force --deep --sign "$CODE_SIGN_IDENTITY" "$APP_DIR"
echo "Built $APP_DIR"
