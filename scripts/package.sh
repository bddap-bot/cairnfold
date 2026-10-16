#!/usr/bin/env bash
# Exports one release build inside shell.nix: package.sh linux-x64|linux-arm64|windows OUT [steam]
# A steam package also carries the GodotSteam extension and Valve's steam_api library; the others never do.
# Linux packages are .tar.gz, Windows a .zip; each holds nestcombe/ with the game binary, notices/ and REVISION.
# The arm64 package, side-loaded on a Steam Frame, also carries its library art in steam/.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
target=$1
out=$(realpath -m "$2")
steam=${3:-}
case $steam in ""|steam) ;; *) echo "package: third argument is steam or nothing" >&2; exit 1 ;; esac
mkdir -p "$(dirname "$out")"
case $target in
  linux-x64) preset="Linux x86_64" binary=nestcombe template=linux_release.x86_64 steam_dir=linux64 ;;
  linux-arm64) preset="Linux arm64" binary=nestcombe template=linux_release.arm64 steam_dir=linuxarm64 ;;
  windows) preset="Windows x86_64" binary=Nestcombe.exe template=windows_release_x86_64.exe steam_dir=win64 ;;
  *) echo "package: no target $target" >&2; exit 1 ;;
esac
. "$root/scripts/pins.sh"
case $(godot4 --version 2>/dev/null) in "$godot_version".stable*) ;; *) echo "package: godot4 is not $godot_version" >&2; exit 1 ;; esac
templates=$(fetch "${godot_templates[@]}")

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
export XDG_DATA_HOME=$stage/data XDG_CONFIG_HOME=$stage/config
tdir=$XDG_DATA_HOME/godot/export_templates/$godot_version.stable
mkdir -p "$tdir"
unzip -p "$templates" "templates/$template" > "$tdir/$template"
echo "$godot_version.stable" > "$tdir/version.txt"

git -C "$root" archive HEAD game | tar -x -C "$stage"
if [ -n "$steam" ]; then
  unzip -q "$(fetch "${godotsteam[@]}")" addons/godotsteam/godotsteam.gdextension "addons/godotsteam/$steam_dir/*" -d "$stage/game"
fi
mkdir -p "$stage/nestcombe"
if ! godot4 --headless --path "$stage/game" --export-release "$preset" "$stage/nestcombe/$binary" > "$stage/export.log" 2>&1 ||
  [ ! -f "$stage/nestcombe/$binary" ]; then
  grep -v Fontconfig "$stage/export.log" | tail -60
  exit 1
fi
if [ "$target" = linux-arm64 ]; then git -C "$root" archive HEAD steam | tar -x -C "$stage/nestcombe"; fi
git -C "$root" rev-parse HEAD > "$stage/nestcombe/REVISION"
"$root/scripts/notices.sh" "$target" "$stage/nestcombe/notices" "$steam"
cp "$root"/LICENSE-* "$stage/nestcombe/"
rm -f "$out"
if [ "$target" = windows ]; then
  (cd "$stage" && zip -qr -X "$out" nestcombe)
else
  tar -czf "$out" -C "$stage" nestcombe
fi
python3 "$root/scripts/notices.py" check "$out" "$stage/nestcombe/notices"
echo "package: $out ($target, $(git -C "$root" rev-parse --short HEAD))"
