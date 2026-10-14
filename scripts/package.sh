#!/usr/bin/env bash
# Builds an aarch64 Linux bundle (pinned Godot runtime + the game) for standalone headsets: package.sh OUT.tar.gz
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(realpath -m "$1")
. "$root/scripts/pins.sh"
zip=$(fetch "${godot_arm64[@]}")
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/cairnfold/bin"
unzip -p "$zip" "Godot_v$godot_version-stable_linux.arm64" > "$stage/cairnfold/bin/godot"
chmod +x "$stage/cairnfold/bin/godot"
git -C "$root" archive HEAD game demo steam | tar -x -C "$stage/cairnfold"
cp "$root/scripts/play.sh" "$stage/cairnfold/play.sh"
git -C "$root" rev-parse HEAD > "$stage/cairnfold/REVISION"
"$root/scripts/notices.sh" frame "$stage/cairnfold/notices"
cp "$root"/LICENSE-* "$stage/cairnfold/"
tar -czf "$out" -C "$stage" cairnfold
python3 "$root/scripts/notices.py" check "$out" "$stage/cairnfold/notices"
echo "package: $out ($(git -C "$root" rev-parse --short HEAD))"
