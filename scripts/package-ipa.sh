#!/bin/bash
set -euo pipefail

version="${1:?Pass a version tag such as v0.1.0}"
if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Release tags must match vMAJOR.MINOR.PATCH" >&2
  exit 1
fi
mkdir -p build/ipa/Payload
xcodebuild -project MailApp.xcodeproj -scheme MailApp -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/ReleaseDerivedData \
  MARKETING_VERSION="${version#v}" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  build | tee build/release-build.log
app_path="build/ReleaseDerivedData/Build/Products/Release-iphoneos/MailApp.app"
test -f "$app_path/MailApp"
ditto "$app_path" build/ipa/Payload/MailApp.app
(cd build/ipa && /usr/bin/zip -qry "../MailApp-${version}.ipa" Payload)
unzip -t "build/MailApp-${version}.ipa"
shasum -a 256 "build/MailApp-${version}.ipa" > "build/MailApp-${version}.ipa.sha256"
