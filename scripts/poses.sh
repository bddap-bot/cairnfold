#!/usr/bin/env bash
# poses.sh OUT_DIR [AVATAR]: AVATAR is a built-in's number (default 0) or a VRM file the guest wears.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(realpath -m "$1")
avatar=${2:-0}
mkdir -p "$out"
rm -f "$out"/*.json "$out"/*.log "$out"/*.png
# shellcheck source=scripts/xvfb.sh
. "$root/scripts/xvfb.sh"
xvfb 2560x1024x24
pids=("$xvfb_pid")
trap 'kill "${pids[@]}" 2>/dev/null || true' EXIT
export VK_ICD_FILENAMES=$desktop_icd
beacon=$((20000 + 4 * (RANDOM % 5000)))
first=$((7480 + 8 * (RANDOM % 7)))
wears=(--avatar "$avatar")
if [ -f "$avatar" ]; then
  rm -rf "$out/avatars"
  mkdir -p "$out/avatars"
  cp "$avatar" "$out/avatars/"
  wears=(--avatars "$out/avatars")
fi
python3 - "$root/demo/poses-host.json" "$out/host.json" "$([ -f "$avatar" ] && echo 1 || echo 0)" <<'PY'
import json, sys
steps = json.load(open(sys.argv[1]))
if sys.argv[3] == "1":
    at = next(i for i, s in enumerate(steps) if s.get("players") == 2)
    steps.insert(at + 1, {"op": "until", "worn": 1, "seconds": 120})
json.dump(steps, open(sys.argv[2], "w"))
PY
cp "$root/demo/poses-guest.json" "$out/guest.json"
game() {
  local name=$1
  shift
  timeout 400 godot4 --path "$root/game" --resolution 1200x900 --xr-mode off -- --desktop --script "$out/$name.json" \
    --capture-dir "$out" --beacon-port "$beacon" --port "$first" --quit-after 360 "$@" >"$out/$name.log" 2>&1 &
  pids+=($!)
}
game host --avatar 0
for _ in $(seq 600); do
  port=$(sed -n 's/^session: hosting on port //p' "$out/host.log" | head -n1)
  [ -n "$port" ] && break
  sleep 0.1
done
[ -n "$port" ] || { echo "poses: the host never opened its garden; see $out/host.log"; exit 1; }
game guest --host-port "$port" "${wears[@]}"
status=0
for pid in "${pids[@]:1}"; do wait "$pid" || status=1; done
for name in host guest; do
  if grep -qE "SCRIPT ERROR|timed out|handle_crash" "$out/$name.log"; then echo "poses: $name failed; see $out/$name.log"; status=1; fi
done
ls "$out"/pose-*.png >/dev/null 2>&1 || { echo "poses: no captures in $out"; status=1; }
exit "$status"
