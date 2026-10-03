#!/bin/bash
set -euo pipefail

version="${1:?Pass a version tag such as v0.1.0}"
if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Release tags must match vMAJOR.MINOR.PATCH" >&2
  exit 1
fi
mkdir -p build/ipa/Payload
xcodebuild -project Dispatch.xcodeproj -scheme Dispatch -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/ReleaseDerivedData \
  MARKETING_VERSION="${version#v}" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  build 2>&1 | tee build/release-build.log
app_path="build/ReleaseDerivedData/Build/Products/Release-iphoneos/Dispatch.app"
test -f "$app_path/Dispatch"
ditto "$app_path" build/ipa/Payload/Dispatch.app
(cd build/ipa && /usr/bin/zip -qry "../Dispatch-${version}.ipa" Payload)
unzip -t "build/Dispatch-${version}.ipa"
shasum -a 256 "build/Dispatch-${version}.ipa" > "build/Dispatch-${version}.ipa.sha256"
