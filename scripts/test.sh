#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/records.sh
runs=$(mktemp -d)
trap 'rm -rf "$runs"' EXIT
# Each test gets its own user:// (the XDG data home), which holds its scratch files: Godot's temp dir is /tmp whatever
# TMPDIR says.
XDG_DATA_HOME=$(mktemp -d -p "$runs")
TMPDIR=$runs
export XDG_DATA_HOME TMPDIR
# A test holds about 300 MB, the GPU checks 1.6 GB. The cap is data, not address space: a GPU check's ~40 glibc
# malloc arenas reserve 1.7-2.0 GB it never touches.
ulimit -d $((4 * 1024 * 1024))
python3 -m unittest discover -s tests -p 'test_*.py' >"$runs/python.log" 2>&1 &
python=$!
scripts/check.sh
status=0
if grep -nE "^\s+quit\(" tests/*.gd; then echo "tests exit through Main.quit, which waits for playing sounds"; status=1; fi
# Largest first, so the longest start early. The hour's timeout only catches hangs: test_house_leaks alone took 29
# minutes on a loaded host, and the suite waits for it anyway.
cat >"$runs/tests.mk" <<'MK'
%.log.exit:
	@XDG_DATA_HOME=$$(mktemp -d -p "$(@D)") scripts/timeout.sh 3600 godot4 --headless --fixed-fps 60 --path game \
	  --script "../tests/$(basename $(basename $(@F)))" >"$(basename $@)" 2>&1; echo $$? >"$@"
MK
fifo=${MAKEFLAGS-}
fifo=${fifo##*--jobserver-auth=fifo:}
if [ -p "${fifo%% *}" ]; then jobs=(); else jobs=(-j "$(( $(nproc) / 2 ))"); fi
# shellcheck disable=SC2046,SC2012
make -s -k -f "$runs/tests.mk" "${jobs[@]}" $(ls -S tests/test_*.gd | sed "s|^tests/\(.*\)|$runs/\1.log.exit|")
errors='SCRIPT ERROR|SHADER ERROR|still in use at exit|leaked at exit|previously freed|initialized RID|initialize the wrong RID|Parameter "material" is null|Parameter "mem|must be normalized'
verdict() {
  local failed=0
  if [ "$3" != 0 ]; then echo "$1: exited $3"; failed=1; fi
  grep -E "^(tests|FAIL):|$4" "$2" | sed "s|^|$1: |" || true
  # A test that stops short of its end, however it exits, never prints its verdict.
  if grep -qE "$4" "$2" || ! grep -q "^tests: ok" "$2"; then failed=1; fi
  if [ "$failed" = 1 ]; then tail -n 60 "$2" | sed "s|^|$1: |"; status=1; fi
}
for t in tests/test_*.gd; do
  log="$runs/$(basename "$t").log"
  verdict "$t" "$log" "$(cat "$log.exit")" "$errors"
done
# The GPU checks compare what the compute shaders lay, so they need the desktop renderer, one at a time.
# shellcheck source=scripts/xvfb.sh
. scripts/xvfb.sh
xvfb 640x480x24
trap 'kill $xvfb_pid ${gpu:-} 2>/dev/null || true; rm -rf "$runs"' EXIT
gpu_errors='SCRIPT ERROR|SHADER ERROR|Parameter "material" is null'
for t in tests/gpu_*.gd; do
  log="$runs/$(basename "$t").log"
  code=0
  VK_ICD_FILENAMES=$desktop_icd XDG_DATA_HOME=$(mktemp -d -p "$runs") \
    scripts/timeout.sh 600 godot4 --path game --fixed-fps 60 --xr-mode off --resolution 64x64 --script "../$t" >"$log" 2>&1 &
  gpu=$!
  wait "$gpu" || code=$?
  verdict "$t" "$log" "$code" "$gpu_errors"
done
if ! wait "$python"; then status=1; fi
cat "$runs/python.log"
exit "$status"
