#!/usr/bin/env bash
# A flat-screen player joins a VR host's garden through the visit tool's figures, walks up and takes a photo; both
# games render under one virtual display: flat.sh OUT_DIR. Each wears its own VRM from its avatars folder: the
# flat-screen player's picker shows the host's, the host's captures show the flat-screen player's standing in its
# garden, and the photo lands in OUT_DIR/photos. Then the flat-screen player holds out the seed dish by the host's
# wall: a conure comes to stand on it in its own game, and in the host's another stands on the dish its avatar holds.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(realpath -m "$1")
mkdir -p "$out"
rm -f "$out"/*.json "$out"/*.log
display=:$((100 + RANDOM % 800))
Xvfb "$display" -screen 0 2560x1024x24 -nolisten tcp &
pids=($!)
trap 'kill "${pids[@]}" 2>/dev/null || true' EXIT
for _ in $(seq 50); do [ -e "/tmp/.X11-unix/X${display#:}" ] && break; sleep 0.1; done
export DISPLAY=$display
export VK_ICD_FILENAMES=${NESTCOMBE_ICD:-/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json}
beacon=$((20000 + 4 * (RANDOM % 5000)))
first=$((7480 + 8 * (RANDOM % 7)))
game() {
  local name=$1 vrm=$2
  shift 2
  rm -rf "$out/avatars-$name"
  mkdir -p "$out/avatars-$name"
  cp "$root/tests/avatars/$vrm" "$out/avatars-$name/"
  timeout 660 godot4 --path "$root/game" --resolution 1200x900 --xr-mode off -- --desktop --script "$root/demo/flat-$name.json" \
    --capture-dir "$out" --beacon-port "$beacon" --port "$first" --quit-after 600 --avatars "$out/avatars-$name" "$@" >"$out/$name.log" 2>&1 &
  pids+=($!)
}
game host godette-0.x.vrm
for _ in $(seq 600); do
  port=$(sed -n 's/^session: hosting on port //p' "$out/host.log" | head -n1)
  [ -n "$port" ] && break
  sleep 0.1
done
[ -n "$port" ] || { echo "flat: the host never opened its garden; see $out/host.log"; exit 1; }
game join crimsom-1.0.vrm --flat --host-port "$port"
status=0
for pid in "${pids[@]:1}"; do wait "$pid" || status=1; done
for name in host join; do
  if grep -qE "SCRIPT ERROR|timed out|handle_crash" "$out/$name.log"; then echo "flat: $name failed; see $out/$name.log"; status=1; fi
done
worn=$(python3 -c 'import json, sys; print(*json.load(open(sys.argv[1]))["worn"])' "$out/host-seen.json" 2>/dev/null || true)
[ "$worn" = "$(sha256sum "$out/avatars-join/crimsom-1.0.vrm" | cut -d' ' -f1)" ] || { echo "flat: the host does not see the flat-screen player's own avatar"; status=1; }
fed=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["fed"]["dish"])' "$out/host-fed.json" 2>/dev/null || true)
[ "${fed:-0}" -ge 1 ] || { echo "flat: the host sees no animal eating at the flat-screen player's dish"; status=1; }
ls "$out"/photos/*.png >/dev/null 2>&1 || { echo "flat: no photo in $out/photos"; status=1; }
exit "$status"
