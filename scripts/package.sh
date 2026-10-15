#!/usr/bin/env bash
# Exports one release build inside shell.nix: package.sh linux-x64|linux-arm64|windows OUT
# Linux packages are .tar.gz, Windows a .zip; each holds cairnfold/ with the game binary, notices/ and REVISION.
# The arm64 package, side-loaded on a Steam Frame, also carries its library art in steam/.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
target=$1
out=$(realpath -m "$2")
mkdir -p "$(dirname "$out")"
case $target in
  linux-x64) preset="Linux x86_64" binary=cairnfold template=linux_release.x86_64 ;;
  linux-arm64) preset="Linux arm64" binary=cairnfold template=linux_release.arm64 ;;
  windows) preset="Windows x86_64" binary=Cairnfold.exe template=windows_release_x86_64.exe ;;
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
mkdir -p "$stage/cairnfold"
if ! godot4 --headless --path "$stage/game" --export-release "$preset" "$stage/cairnfold/$binary" > "$stage/export.log" 2>&1 ||
  [ ! -f "$stage/cairnfold/$binary" ]; then
  grep -v Fontconfig "$stage/export.log" | tail -60
  exit 1
fi
if [ "$target" = linux-arm64 ]; then git -C "$root" archive HEAD steam | tar -x -C "$stage/cairnfold"; fi
git -C "$root" rev-parse HEAD > "$stage/cairnfold/REVISION"
"$root/scripts/notices.sh" "$target" "$stage/cairnfold/notices"
cp "$root"/LICENSE-* "$stage/cairnfold/"
rm -f "$out"
if [ "$target" = windows ]; then
  (cd "$stage" && zip -qr -X "$out" cairnfold)
else
  tar -czf "$out" -C "$stage" cairnfold
fi
python3 "$root/scripts/notices.py" check "$out" "$stage/cairnfold/notices"
echo "package: $out ($target, $(git -C "$root" rev-parse --short HEAD))"
