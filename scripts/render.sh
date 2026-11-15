#!/usr/bin/env bash
# render.sh SCRIPT.json|CHUNK.jsonl OUT_DIR [ENGINE_ARGS...]; a record replays as docs/replay.md describes.
# CAIRNFOLD_AVATARS: the avatars folder pulled off the recording device. CAIRNFOLD_QUIT_AFTER: game seconds (120 for a
# script). CAIRNFOLD_TIMEOUT: wall seconds (1800).
set -euo pipefail
source=$(realpath "$1")
out=$(realpath -m "$2")
shift 2
mkdir -p "$out"
if [[ $source == *.jsonl ]]; then
  play=(--replay "$source")
  if [ -n "${CAIRNFOLD_QUIT_AFTER:-}" ]; then play+=(--quit-after "$CAIRNFOLD_QUIT_AFTER"); fi
else
  play=(--script "$source" --quit-after "${CAIRNFOLD_QUIT_AFTER:-120}")
fi
if [ -n "${CAIRNFOLD_AVATARS:-}" ]; then play+=(--avatars "$(realpath "$CAIRNFOLD_AVATARS")"); fi
if [ -n "${CAIRNFOLD_CAMERA:-}" ]; then play+=(--camera "$(realpath "$CAIRNFOLD_CAMERA")"); fi
cd "$(dirname "$0")/../game"
# shellcheck source=scripts/xvfb.sh
. ../scripts/xvfb.sh
xvfb 3840x2160x24
trap 'kill $xvfb_pid 2>/dev/null || true' EXIT
export VK_ICD_FILENAMES=$desktop_icd
timeout "${CAIRNFOLD_TIMEOUT:-1800}" godot4 --path . --resolution 1600x1200 --xr-mode off "$@" -- --desktop "${play[@]}" --capture-dir "$out" --metrics "$out/metrics.json"
