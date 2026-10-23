#!/usr/bin/env bash
# Imports the project headless and fails on any script error, then fails on any use of a member Main lacks: Godot
# reports one as an error only with unsafe access raised to an error, which a game build must not do to every script.
set -euo pipefail
cd "$(dirname "$0")/../game"
imported=$(godot4 --headless --path . --import 2>&1)
if grep -E "SCRIPT ERROR|Parse Error|Compile Error|Failed to load" <<<"$imported"; then exit 1; fi
trap 'rm -f override.cfg' EXIT
printf '[debug]\ngdscript/warnings/unsafe_property_access=2\ngdscript/warnings/unsafe_method_access=2\n' >override.cfg
compiled=$(godot4 --headless --path . --script ../scripts/compile.gd 2>&1)
if grep -A1 -E 'on the inferred type "Main"' <<<"$compiled"; then exit 1; fi
echo "check: scripts compile"
