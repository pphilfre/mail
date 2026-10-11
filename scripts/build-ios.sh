#!/bin/bash
set -euo pipefail

mkdir -p build
xcodebuild -project Dispatch.xcodeproj -scheme Dispatch -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  build 2>&1 | tee build/build.log
codesign -d --entitlements - build/DerivedData/Build/Products/Debug-iphonesimulator/Dispatch.app \
  2>&1 | tee build/simulator-signing.log
