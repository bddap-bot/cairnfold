#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
godot4 --headless --path game --import > /dev/null 2>&1
godot4 --headless --fixed-fps 60 --path game --script ../tests/test_shaders.gd -- --write
