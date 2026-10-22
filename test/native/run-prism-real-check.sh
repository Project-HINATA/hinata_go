#!/bin/sh
# Runs the real App Clip sources against a live PRiSM end-to-end stack (see PRiSM scripts/e2e-ha): the
# platform under `wrangler dev`, Home Assistant in docker and the macOS build of the firmware's IO
# client. Needs `.e2e/platform.json` and `.e2e/ha.json` in the PRiSM checkout, so it is run by hand,
# not in CI.
#
#   PRISM_E2E_ROOT=/path/to/PRiSM test/native/run-prism-real-check.sh
set -eu
cd "$(dirname "$0")/../.."
root=${PRISM_E2E_ROOT:-$HOME/Projects/PRiSM}
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
eval "$(python3 - "$root" <<'PY'
import json, shlex, sys
root = sys.argv[1]
cfg = json.load(open(f"{root}/.e2e/platform.json"))
env = {
    "PRISM_E2E_ROOT": root,
    "PRISM_E2E_ORIGIN": cfg["origin"],
    "PRISM_E2E_SHOP": cfg["shop"]["publicId"],
    "PRISM_E2E_PLAYER_TOKEN": cfg["player"]["token"],
    "PRISM_E2E_LOUNGE": cfg["devices"]["lounge"]["publicId"],
    "PRISM_E2E_A": cfg["devices"]["a"]["publicId"],
    "PRISM_E2E_HA_URL": cfg["ha"]["url"],
    "PRISM_E2E_HA_TOKEN": cfg["ha"]["adminToken"],
    "PRISM_E2E_IO_DIR": f"{root}/.e2e/io",
}
for key, value in env.items():
    print(f"export {key}={shlex.quote(value)}")
PY
)"
export PRISM_E2E_IO_BIN=${PRISM_E2E_IO_BIN:-$HOME/Projects/hinata-aimeio-rs/tools/mac-test/target/debug/io_sim}
swiftc -parse-as-library ios/PrismClip/InvocationParser.swift ios/PrismClip/InvocationRouter.swift ios/PrismClip/Models.swift ios/PrismClip/PrismAPI.swift ios/PrismClip/MachineLoginViewModel.swift test/native/prism_visit_fixtures.swift test/native/prism_real_check.swift -o "$check_dir/prism-real-check"
"$check_dir/prism-real-check"
