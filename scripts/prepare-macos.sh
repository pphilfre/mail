#!/bin/bash
set -euo pipefail

# Pin the SDK/compiler, and fail instead of silently switching Xcode versions.
sudo xcode-select --switch /Applications/Xcode_26.6.app/Contents/Developer
xcodebuild -version
xcodebuild -showsdks
if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi
xcodegen --version
xcodegen generate --spec project.yml
