#!/usr/bin/env bash
# Imports the project headless and fails on any script error, game or test, then on any use of a member Main lacks:
# Godot reports one as an error only with unsafe access raised to an error, which no build may do to every script.
set -euo pipefail
cd "$(dirname "$0")/../game"
# run ARGS...: what Godot prints; a crash prints it all and fails the check, which set -e would end silently.
run() {
  local out code=0
  out=$(godot4 --headless --path . "$@" 2>&1) || code=$?
  [ "$code" = 0 ] || { printf '%s\n' "$out" >&2; echo "check: godot4 $* exited $code" >&2; exit 1; }
  printf '%s\n' "$out"
}
errors="SCRIPT ERROR|Parse Error|Compile Error|Failed to load"
imported=$(run --import)
if grep -E "$errors" <<<"$imported"; then exit 1; fi
compiled=$(run --script ../scripts/compile.gd)
if grep -A1 -E "$errors" <<<"$compiled"; then exit 1; fi
trap 'rm -f override.cfg' EXIT
printf '[debug]\ngdscript/warnings/unsafe_property_access=2\ngdscript/warnings/unsafe_method_access=2\n' >override.cfg
compiled=$(run --script ../scripts/compile.gd)
if grep -A1 -E 'on the inferred type "Main"' <<<"$compiled"; then exit 1; fi
echo "check: scripts compile"
