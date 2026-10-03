#!/bin/bash
set -euo pipefail

mkdir -p build
simulator_id="$(python3 scripts/select-simulator.py)"
xcrun simctl boot "$simulator_id" || xcrun simctl list devices booted | grep -F "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b
destination="platform=iOS Simulator,id=$simulator_id"
common=(-project Dispatch.xcodeproj -scheme Dispatch -configuration Debug
  -destination "$destination" -derivedDataPath build/DerivedData
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
xcodebuild "${common[@]}" test -parallel-testing-enabled NO \
  -resultBundlePath build/Tests.xcresult 2>&1 | tee build/test.log
