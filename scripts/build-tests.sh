#!/bin/bash
set -euo pipefail
mkdir -p build
xcodebuild -project Dispatch.xcodeproj -scheme Dispatch -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -enableCodeCoverage "${DISPATCH_COVERAGE:-NO}" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build-for-testing 2>&1 | tee build/build.log
codesign -d --entitlements - build/DerivedData/Build/Products/Debug-iphonesimulator/Dispatch.app \
  2>&1 | tee build/simulator-signing.log
# Tar preserves executable bits and symlinks across artifact upload/download.
tar -C build/DerivedData/Build -czf build/test-products.tar.gz Products
python3 scripts/cache-inputs.py save build/input-times.json
