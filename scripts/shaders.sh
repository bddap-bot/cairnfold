#!/usr/bin/env bash
# Rewrites game/shaders.tres, the materials the export's shader baker compiles (tests/test_shaders.gd), from what a
# booted game makes.
set -euo pipefail
cd "$(dirname "$0")/.."
godot4 --headless --path game --import > /dev/null 2>&1 || true
godot4 --headless --fixed-fps 60 --path game --script ../tests/test_shaders.gd -- --write
