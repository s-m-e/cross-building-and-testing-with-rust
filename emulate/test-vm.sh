#!/bin/sh
# Build the cargo test binary for one emulation architecture, boot the
# matching Alpine guest with that test binary in place of the demo binary,
# and report pass/fail from the libtest output captured on the guest serial
# console.
#
# Usage: emulate/test-vm.sh <x86_64|armv7|aarch64>
# Driven by the justfile `emulate-test-vm-*` recipes.
set -eu

arch=${1:?usage: test-vm.sh <x86_64|armv7|aarch64>}
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")

case "$arch" in
    x86_64)  triple=x86_64-unknown-linux-musl ;;
    armv7)   triple=armv7-unknown-linux-musleabihf ;;
    aarch64) triple=aarch64-unknown-linux-musl ;;
    *)       echo "test-vm.sh: unknown architecture '$arch'" >&2; exit 2 ;;
esac

command -v jq >/dev/null \
    || { echo "test-vm.sh: jq is required to parse cargo JSON output" >&2; exit 1; }

# Build the test binary (static musl + hardware feature) without running it,
# then extract the lib unittest executable path from cargo's JSON output.
# The bin's unittest binary contains no tests; the lib's contains all of
# them, including the musl-only `vm_emulated_nic_is_a_qemu_chip` test.
echo ">>> $arch: building test binary"
test_bin=$(cargo test --release --target "$triple" --features hardware \
                --no-run --message-format=json \
            | jq -r 'select(.profile.test == true)
                     | select(.target.kind[0] == "lib")
                     | .executable' \
            | head -1)
[ -n "$test_bin" ] && [ -f "$test_bin" ] \
    || { echo "test-vm.sh: could not locate the test binary" >&2; exit 1; }
echo ">>> $arch: test binary = ${test_bin#"$root"/}"

# Boot the guest with the test binary as its payload; tee the serial output
# to both a log file (for verdict-grepping) and the terminal (so the user
# sees libtest's progress live).
log=$(mktemp -t crossdemo-vm-test.XXXXXX.log)
trap 'rm -f "$log"' EXIT
"$here/run.sh" "$arch" "$test_bin" 2>&1 | tee "$log"

# Read libtest's verdict from the captured serial output.
if grep -q 'test result: FAILED' "$log" || ! grep -q 'test result: ok' "$log"; then
    echo ">>> $arch: tests FAILED in VM" >&2
    exit 1
fi
echo ">>> $arch: tests passed in VM"
