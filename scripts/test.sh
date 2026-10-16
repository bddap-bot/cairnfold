#!/usr/bin/env bash
# The repo's checks: scripts compile, then every headless test; a script error, a failed allocation or a resource left
# in use at exit fails it.
set -euo pipefail
cd "$(dirname "$0")/.."
# Godot's user:// lives under the XDG data home: each run gets its own, so runs side by side share no files.
XDG_DATA_HOME=$(mktemp -d)
export XDG_DATA_HOME
trap 'rm -rf "$XDG_DATA_HOME"' EXIT
# A test holds about 300 MB; a runaway allocation fails its test at 4 GB instead of exhausting the machine.
ulimit -v $((4 * 1024 * 1024))
python3 -m unittest discover -s tests -p 'test_*.py'
scripts/check.sh
status=0
if grep -nE "^\s+quit\(" tests/*.gd; then echo "tests exit through Main.quit, which waits for playing sounds"; status=1; fi
for t in tests/test_*.gd; do
  failed=0
  out=$(godot4 --headless --path game --script "../$t" 2>&1) || { echo "$t: exited $?"; failed=1; }
  grep -E "^(tests|FAIL):|SCRIPT ERROR|still in use at exit|Parameter \"mem" <<<"$out" | sed "s|^|$t: |"
  if grep -qE "SCRIPT ERROR|still in use at exit|Parameter \"mem" <<<"$out"; then failed=1; fi
  # A failure seen once is kept in the run's log, crash backtraces and errors around it included.
  if [ "$failed" = 1 ]; then tail -n 60 <<<"$out" | sed "s|^|$t: |"; status=1; fi
done
exit "$status"
