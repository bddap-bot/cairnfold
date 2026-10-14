#!/usr/bin/env bash
# The repo's checks: scripts compile, then every headless test; a script error in a test fails it.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest discover -s tests -p 'test_*.py'
scripts/check.sh
status=0
for t in tests/test_*.gd; do
  out=$(godot4 --headless --path game --script "../$t" 2>&1) || status=1
  grep -E "^(tests|FAIL):|SCRIPT ERROR" <<<"$out" | sed "s|^|$t: |"
  if grep -q "SCRIPT ERROR" <<<"$out"; then status=1; fi
done
exit "$status"
