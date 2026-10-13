#!/usr/bin/env bash
# The repo's checks: scripts compile, then the headless wall tests.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/check.sh
godot4 --headless --path game --script ../tests/test_wall.gd 2>&1 | grep -vE "^Godot Engine|^$"
exit "${PIPESTATUS[0]}"
