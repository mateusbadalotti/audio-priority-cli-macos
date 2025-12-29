#!/bin/bash
set -e

echo "Building AudioPriority CLI..."

xcodebuild -scheme AudioPriority \
  -configuration Release \
  -derivedDataPath .build \
  -arch arm64 -arch x86_64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

mkdir -p dist
rm -f dist/audio-priority
cp .build/Build/Products/Release/audio-priority dist/
chmod +x dist/audio-priority

echo ""
echo "Build complete: dist/audio-priority"
