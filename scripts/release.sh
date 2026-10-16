#!/usr/bin/env bash
# Publishes HEAD as a GitHub release carrying every build: Windows and Linux (x86_64, and arm64 for the Steam Frame)
# exports, the Frame's Android APK and the Quest APK.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
. scripts/pins.sh
rev=$(git rev-parse HEAD)
tag=r$(build_number .)
git fetch -q origin
git merge-base --is-ancestor "$rev" origin/main || { echo "release: $rev is not on origin/main" >&2; exit 1; }
! gh release view "$tag" > /dev/null 2>&1 || { echo "release: $tag exists" >&2; exit 1; }
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for target in linux-x64 linux-arm64; do nix-shell --run "scripts/package.sh $target '$out/nestcombe-$target.tar.gz'"; done
nix-shell --run "scripts/package.sh windows '$out/nestcombe-windows.zip'"
for target in quest lepton; do nix-shell android.nix --run "scripts/android.sh $target '$out/nestcombe-$target.apk'"; done
gh release create "$tag" --target "$rev" --title "$(sed -n 's/^config\/name="\(.*\)"$/\1/p' game/project.godot) $tag" \
  --notes "Built from $rev. PC VR: nestcombe-windows.zip or nestcombe-linux-x64.tar.gz, run Nestcombe.exe or nestcombe/nestcombe with an OpenXR runtime (SteamVR). Steam Frame: nestcombe-lepton.apk for an Android depot, or nestcombe-linux-arm64.tar.gz (README, \"Running\"). Quest: install nestcombe-quest.apk (README, \"Quest\")." \
  "$out/nestcombe-quest.apk" "$out/nestcombe-lepton.apk" "$out/nestcombe-linux-x64.tar.gz" "$out/nestcombe-linux-arm64.tar.gz" "$out/nestcombe-windows.zip"
