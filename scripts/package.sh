#!/usr/bin/env bash
# Exports one release build inside shell.nix: package.sh linux-x64|linux-arm64|windows OUT [steam]
# A steam package also carries the GodotSteam extension and Valve's steam_api library; the others never do.
# Linux packages are .tar.gz, Windows a .zip; each holds cairnfold/ with the game binary, notices/ and REVISION.
# The arm64 package, side-loaded on a Steam Frame, also carries its library art in steam/.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
target=$1
out=$(realpath -m "$2")
steam=${3:-}
case $steam in ""|steam) ;; *) echo "package: third argument is steam or nothing" >&2; exit 1 ;; esac
mkdir -p "$(dirname "$out")"
case $target in
  linux-x64) preset="Linux x86_64" binary=cairnfold template=linux_release.x86_64 steam_dir=linux64 ;;
  linux-arm64) preset="Linux arm64" binary=cairnfold template=linux_release.arm64 steam_dir=linuxarm64 ;;
  windows) preset="Windows x86_64" binary=Cairnfold.exe template=windows_release_x86_64.exe steam_dir=win64 ;;
  *) echo "package: no target $target" >&2; exit 1 ;;
esac
# shellcheck source=scripts/stage.sh
. "$root/scripts/stage.sh"
mkdir -p "$stage/cairnfold"
"$root/scripts/export.sh" "$stage/game" "$preset" "$stage/cairnfold/$binary" "$stage/export.log"
if [ "$target" = linux-arm64 ]; then git -C "$root" archive HEAD steam | tar -x -C "$stage/cairnfold"; fi
git -C "$root" rev-parse HEAD > "$stage/cairnfold/REVISION"
"$root/scripts/notices.sh" "$target" "$stage/cairnfold/notices" "$steam"
cp "$root"/LICENSE-* "$stage/cairnfold/"
rm -f "$out"
if [ "$target" = windows ]; then
  (cd "$stage" && zip -qr -X "$out" cairnfold)
else
  tar -czf "$out" -C "$stage" cairnfold
fi
python3 "$root/scripts/notices.py" check "$out" "$stage/cairnfold/notices"
echo "package: $out ($target, $(git -C "$root" rev-parse --short HEAD))"
