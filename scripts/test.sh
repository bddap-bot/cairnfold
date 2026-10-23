#!/usr/bin/env bash
# The repo's checks: scripts compile, then every headless test; a script error, a failed allocation, an engine math call
# given an unnormalized axis or a resource left
# in use at exit or an engine call given a freed object fails it.
set -euo pipefail
cd "$(dirname "$0")/.."
runs=$(mktemp -d)
trap 'rm -rf "$runs"' EXIT
# Godot's user:// lives under the XDG data home: each run, and each test in it, gets its own, so none share files. Tests
# keep their scratch files there, since Godot's temp dir is /tmp whatever TMPDIR says; TMPDIR holds everything else's.
XDG_DATA_HOME=$(mktemp -d -p "$runs")
TMPDIR=$runs
export XDG_DATA_HOME TMPDIR
# A test holds about 300 MB; a runaway allocation fails its test at 4 GB instead of exhausting the machine.
ulimit -v $((4 * 1024 * 1024))
python3 -m unittest discover -s tests -p 'test_*.py' >"$runs/python.log" 2>&1 &
python=$!
scripts/check.sh
status=0
if grep -nE "^\s+quit\(" tests/*.gd; then echo "tests exit through Main.quit, which waits for playing sounds"; status=1; fi
# Tests run side by side, largest first so the longest start early; each gets its own user://. A test waits on what the
# game's workers are doing, never on a frame count, and an until() still unmet after two minutes of the host's time
# fails as the wait it names. The timeout catches any other hang, and stays an hour: test_house_leaks alone took 29
# minutes in a full run on a loaded host, and the suite waits for it anyway, so a lower ceiling would only fail it.
# shellcheck disable=SC2011,SC2016
ls -S tests/test_*.gd | xargs -P "$(( $(nproc) / 2 ))" -I{} sh -c '
  log="$1/$(basename "$2").log"
  XDG_DATA_HOME=$(mktemp -d -p "$1") timeout 3600 godot4 --headless --fixed-fps 60 --path game --script "../$2" >"$log" 2>&1
  echo $? >"$log.exit"' sh "$runs" {}
for t in tests/test_*.gd; do
  log="$runs/$(basename "$t").log"
  code=$(cat "$log.exit")
  failed=0
  if [ "$code" != 0 ]; then echo "$t: exited $code"; failed=1; fi
  grep -E "^(tests|FAIL):|SCRIPT ERROR|still in use at exit|previously freed|Parameter \"mem|must be normalized" "$log" | sed "s|^|$t: |" || true
  if grep -qE "SCRIPT ERROR|still in use at exit|previously freed|Parameter \"mem|must be normalized" "$log"; then failed=1; fi
  # A test that stops short of its end, however it exits, never prints its verdict.
  if ! grep -q "^tests: ok" "$log"; then failed=1; fi
  # A failure seen once is kept in the run's log, crash backtraces and errors around it included.
  if [ "$failed" = 1 ]; then tail -n 60 "$log" | sed "s|^|$t: |"; status=1; fi
done
# The GPU checks compare what the compute shaders lay, so they run on the desktop renderer under a virtual display, as
# scripts/render.sh does, one at a time.
display=:$((100 + RANDOM % 800))
Xvfb "$display" -screen 0 640x480x24 -nolisten tcp &
xvfb=$!
trap 'kill $xvfb 2>/dev/null || true; rm -rf "$runs"' EXIT
for _ in $(seq 50); do [ -e "/tmp/.X11-unix/X${display#:}" ] && break; sleep 0.1; done
for t in tests/gpu_*.gd; do
  log="$runs/$(basename "$t").log"
  code=0
  DISPLAY=$display VK_ICD_FILENAMES=${NESTCOMBE_ICD:-/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json} XDG_DATA_HOME=$(mktemp -d -p "$runs") \
    timeout 600 godot4 --path game --fixed-fps 60 --xr-mode off --resolution 64x64 --script "../$t" >"$log" 2>&1 || code=$?
  grep -E "^(tests|FAIL):|SCRIPT ERROR" "$log" | sed "s|^|$t: |" || true
  if [ "$code" != 0 ] || grep -qE "SCRIPT ERROR" "$log" || ! grep -q "^tests: ok" "$log"; then echo "$t: exited $code"; tail -n 60 "$log" | sed "s|^|$t: |"; status=1; fi
done
if ! wait "$python"; then status=1; fi
cat "$runs/python.log"
exit "$status"
