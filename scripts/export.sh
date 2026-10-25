#!/usr/bin/env bash
# Exports a preset: export.sh GAME_DIR PRESET OUT LOG, printing the log's tail when it fails.
# A preset with shader_baker/enabled ships its shaders compiled, which the baker does only from an editor running a
# RenderingDevice renderer, never a headless one: a Quest 2 with its data cleared sat 52 s on its first frame compiling
# them, 34 s baked. So the editor runs on a virtual display through Mesa's software Vulkan, the nix shell's
# (CAIRNFOLD_LAVAPIPE): a host's driver is built against the host's C library, which the shell's Godot may predate.
set -euo pipefail
game=$1 preset=$2 out=$3 log=$4
display=:$((100 + RANDOM % 800))
Xvfb "$display" -screen 0 640x480x24 -nolisten tcp 2> /dev/null &
xvfb=$!
trap 'kill $xvfb 2> /dev/null || true' EXIT
for _ in $(seq 50); do [ -e "/tmp/.X11-unix/X${display#:}" ] && break; sleep 0.1; done
# Godot 4.5 and 4.6 segfault in about one cold import of twenty, in ClassDB's default-value cache while saving an
# imported scene; the second attempt starts from the first one's import cache, so only a crash is retried.
for attempt in 1 2; do
  DISPLAY=$display VK_ICD_FILENAMES=$CAIRNFOLD_LAVAPIPE \
    godot4 --path "$game" --export-release "$preset" "$out" > "$log" 2>&1 && [ -f "$out" ] && exit 0
  grep -v Fontconfig "$log" | tail -60 || true
  if [ "$attempt" = 2 ] || ! grep -q handle_crash "$log"; then exit 1; fi
  echo "export: Godot crashed exporting; retrying once" >&2
done
