#!/bin/bash
set -euo pipefail
shard="${1:?Pass shard index}"
scope="${DISPATCH_TEST_SCOPE:-full}"
mkdir -p build/DerivedData/Build
simulator_id="$(python3 scripts/select-simulator.py)"
(
  xcrun simctl boot "$simulator_id" || xcrun simctl list devices booted | grep -F "$simulator_id"
  xcrun simctl bootstatus "$simulator_id" -b
) > build/simulator-boot.log 2>&1 &
boot_pid=$!
trap 'kill "$boot_pid" 2>/dev/null || true' EXIT
tar -C build/DerivedData/Build -xzf build/test-products.tar.gz
xctestruns=(build/DerivedData/Build/Products/*.xctestrun)
[[ ${#xctestruns[@]} -eq 1 && -f "${xctestruns[0]}" ]]
selectors=()
if [[ -n "${DISPATCH_TEST_ONLY:-}" ]]; then
  selectors+=(-only-testing:"$DISPATCH_TEST_ONLY")
else
  if [[ "$shard" == 0 ]]; then selectors+=(-only-testing:DispatchTests); fi
  python3 scripts/test-shards.py --scope "$scope" --shard "$shard" > build/test-selectors.txt
  while IFS= read -r selector; do selectors+=(-only-testing:"$selector"); done < build/test-selectors.txt
fi
wait "$boot_pid"
trap - EXIT
xcodebuild test-without-building -xctestrun "${xctestruns[0]}" \
  -destination "platform=iOS Simulator,id=$simulator_id" -parallel-testing-enabled NO \
  -resultBundlePath build/Tests.xcresult "${selectors[@]}" 2>&1 | tee build/test.log
if [[ "$shard" == 0 && -z "${DISPATCH_TEST_ONLY:-}" ]]; then
  app_container="$(xcrun simctl get_app_container "$simulator_id" dev.freddiephilpot.dispatch data)"
  python3 scripts/verify-compose-mime.py "$app_container/Library/Application Support/Dispatch/compose-mime-fixture.eml"
fi
