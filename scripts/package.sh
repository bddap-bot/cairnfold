#!/usr/bin/env bash
# Builds an aarch64 Linux bundle (pinned Godot runtime + the game) for standalone headsets: package.sh OUT.tar.gz
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(realpath -m "$1")
url=https://github.com/godotengine/godot/releases/download/4.5.1-stable/Godot_v4.5.1-stable_linux.arm64.zip
sha=4a2c6bd5066aca9d207c75f540645e29272b129f2cf321d8ba30d922af11b00f
cache=${XDG_CACHE_HOME:-$HOME/.cache}/cairnfold
mkdir -p "$cache"
zip=$cache/${url##*/}
if ! { [ -f "$zip" ] && echo "$sha  $zip" | sha256sum -c --quiet; }; then
  curl -fsSL --max-time 300 -o "$zip.part" "$url"
  echo "$sha  $zip.part" | sha256sum -c --quiet
  mv "$zip.part" "$zip"
fi
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/cairnfold/bin"
unzip -p "$zip" Godot_v4.5.1-stable_linux.arm64 > "$stage/cairnfold/bin/godot"
chmod +x "$stage/cairnfold/bin/godot"
git -C "$root" archive HEAD game demo | tar -x -C "$stage/cairnfold"
cp "$root/scripts/play.sh" "$stage/cairnfold/play.sh"
git -C "$root" rev-parse HEAD > "$stage/cairnfold/REVISION"
tar -czf "$out" -C "$stage" cairnfold
echo "package: $out ($(git -C "$root" rev-parse --short HEAD))"
