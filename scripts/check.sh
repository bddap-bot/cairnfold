#!/usr/bin/env bash
# Imports the project headless and fails on any script error.
set -euo pipefail
cd "$(dirname "$0")/../game"
out=$(godot4 --headless --path . --import 2>&1)
if grep -E "SCRIPT ERROR|Parse Error|Compile Error|Failed to load" <<<"$out"; then exit 1; fi
echo "check: scripts compile"
