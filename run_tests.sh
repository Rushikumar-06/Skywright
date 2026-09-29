#!/usr/bin/env bash
# Runs every test headless and exits non-zero if any fail.
#   ./run_tests.sh            all tests
#   ./run_tests.sh session    only test files whose name contains "session"
# Set GODOT to use a Godot binary other than the one on PATH.
set -euo pipefail
cd "$(dirname "$0")"
godot="${GODOT:-godot}"
# Importing builds Godot's class cache, which class_name scripts need on a fresh checkout.
if ! "$godot" --headless --import >/dev/null 2>&1; then
	echo "Import failed. Run '$godot --headless --import' to see why." >&2
	exit 1
fi
exec timeout 600 "$godot" --headless --fixed-fps 60 --script res://tests/run_tests.gd -- "$@"
