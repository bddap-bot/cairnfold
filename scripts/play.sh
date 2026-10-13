#!/bin/sh
# Launcher inside the bundle; extra arguments go to the game (see game/src/main.gd).
set -eu
d=$(dirname "$(readlink -f "$0")")
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DISPLAY="${DISPLAY:-:0}"
mkdir -p "$d/log"
[ -f "$d/game/.godot/global_script_class_cache.cfg" ] || "$d/bin/godot" --headless --path "$d/game" --import > "$d/log/import.log" 2>&1
exec "$d/bin/godot" --path "$d/game" -- "$@" > "$d/log/last.log" 2>&1
