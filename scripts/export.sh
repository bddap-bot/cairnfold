#!/usr/bin/env bash
# The shader baker runs only in an editor on a RenderingDevice renderer, never headless (a cleared Quest 2 sat 52 s on
# its first frame compiling, 34 s baked), and sees only exported materials, hence game/shaders.tres. Mesa's software
# Vulkan, as a host driver is built against a C library the shell's Godot may predate.
set -euo pipefail
game=$1 preset=$2 out=$3 log=$4
# shellcheck source=scripts/xvfb.sh
. "$(dirname "$0")/xvfb.sh"
xvfb 640x480x24 2> /dev/null || { echo "export: Xvfb started no display" >&2; exit 1; }
trap 'kill $xvfb_pid 2> /dev/null || true' EXIT
# Godot 4.5 and 4.6 segfault in about one cold import of twenty (ClassDB's default-value cache); the retry reuses the
# first attempt's import cache.
for attempt in 1 2; do
  VK_ICD_FILENAMES=$CAIRNFOLD_LAVAPIPE \
    godot4 --path "$game" --export-release "$preset" "$out" > "$log" 2>&1 && [ -f "$out" ] && exit 0
  grep -v Fontconfig "$log" | tail -60 || true
  if [ "$attempt" = 2 ] || ! grep -q handle_crash "$log"; then exit 1; fi
  echo "export: Godot crashed exporting; retrying once" >&2
done
