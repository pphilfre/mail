#!/bin/bash
set -euo pipefail

mkdir -p build
xcodebuild -project Dispatch.xcodeproj -scheme Dispatch -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee build/build.log
