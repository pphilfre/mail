#!/bin/bash
set -euo pipefail

mkdir -p build
simulator_id="$(python3 scripts/select-simulator.py)"
# Boot and migrate the simulator while Xcode compiles the test bundles.
(
  xcrun simctl boot "$simulator_id" || xcrun simctl list devices booted | grep -F "$simulator_id"
  xcrun simctl bootstatus "$simulator_id" -b
) > build/simulator-boot.log 2>&1 &
boot_pid=$!
trap 'kill "$boot_pid" 2>/dev/null || true' EXIT
destination="platform=iOS Simulator,id=$simulator_id"
common=(-project Dispatch.xcodeproj -scheme Dispatch -configuration Debug
  -destination "$destination" -derivedDataPath build/DerivedData
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= ONLY_ACTIVE_ARCH=YES)
xcodebuild "${common[@]}" build-for-testing 2>&1 | tee build/build.log
codesign -d --entitlements - build/DerivedData/Build/Products/Debug-iphonesimulator/Dispatch.app \
  2>&1 | tee build/simulator-signing.log
wait "$boot_pid"
trap - EXIT
if [[ -n "${DISPATCH_TEST_ONLY:-}" ]]; then
  common+=(-only-testing:"$DISPATCH_TEST_ONLY")
fi
xcodebuild "${common[@]}" test-without-building -parallel-testing-enabled NO \
  -resultBundlePath build/Tests.xcresult 2>&1 | tee build/test.log
