#!/usr/bin/env bash
# The repo's checks: scripts compile, then every headless test; a script error or a resource left in use at exit fails it.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest discover -s tests -p 'test_*.py'
scripts/check.sh
status=0
if grep -nE "^\s+quit\(" tests/*.gd; then echo "tests exit through Main.quit, which waits for playing sounds"; status=1; fi
for t in tests/test_*.gd; do
  out=$(godot4 --headless --path game --script "../$t" 2>&1) || status=1
  grep -E "^(tests|FAIL):|SCRIPT ERROR|still in use at exit" <<<"$out" | sed "s|^|$t: |"
  if grep -qE "SCRIPT ERROR|still in use at exit" <<<"$out"; then status=1; fi
done
exit "$status"
