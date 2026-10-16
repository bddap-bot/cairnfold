#!/usr/bin/env bash
# Plays a demo script on the desktop renderer under a virtual display: render.sh SCRIPT.json OUT_DIR [ENGINE_ARGS...]
# Recording a movie records the game's own audio mix too: render.sh SCRIPT OUT --write-movie OUT/x.avi --fixed-fps 30
set -euo pipefail
script=$(realpath "$1")
out=$(realpath -m "$2")
shift 2
mkdir -p "$out"
cd "$(dirname "$0")/../game"
display=:$((100 + RANDOM % 800))
Xvfb "$display" -screen 0 3840x2160x24 -nolisten tcp &
xvfb=$!
trap 'kill $xvfb 2>/dev/null || true' EXIT
for _ in $(seq 50); do [ -e "/tmp/.X11-unix/X${display#:}" ] && break; sleep 0.1; done
export DISPLAY=$display
export VK_ICD_FILENAMES=${NESTCOMBE_ICD:-/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json}
timeout "${NESTCOMBE_TIMEOUT:-1800}" godot4 --path . --resolution 1600x1200 --xr-mode off "$@" -- --desktop --script "$script" --capture-dir "$out" --metrics "$out/metrics.json" --quit-after "${NESTCOMBE_QUIT_AFTER:-120}"
