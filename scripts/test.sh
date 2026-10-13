#!/usr/bin/env bash
# The repo's checks: scripts compile, then every headless test.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/check.sh
status=0
for t in tests/test_*.gd; do
  out=$(godot4 --headless --path game --script "../$t" 2>&1) || status=1
  grep -E "^(tests|FAIL):" <<<"$out" | sed "s|^|$t: |"
done
exit "$status"
