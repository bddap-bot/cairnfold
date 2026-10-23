#!/usr/bin/env bash
# Exports a preset: export.sh GAME_DIR PRESET OUT LOG
# A preset with shader_baker/enabled ships its shaders compiled, which the baker does only from an editor running a
# RenderingDevice renderer, never a headless one: a Quest 2 that compiled them itself sat 50 s on the first frame after
# an install and 11 s on the first easel. So the editor runs on a virtual display through Mesa's software Vulkan.
set -euo pipefail
game=$1 preset=$2 out=$3 log=$4
display=:$((100 + RANDOM % 800))
Xvfb "$display" -screen 0 640x480x24 -nolisten tcp 2> /dev/null &
xvfb=$!
trap 'kill $xvfb 2> /dev/null || true' EXIT
for _ in $(seq 50); do [ -e "/tmp/.X11-unix/X${display#:}" ] && break; sleep 0.1; done
DISPLAY=$display VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/lvp_icd.x86_64.json \
  godot4 --path "$game" --export-release "$preset" "$out" > "$log" 2>&1
