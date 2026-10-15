#!/usr/bin/env bash
# Publishes HEAD as a GitHub release carrying every build: Windows and Linux (x86_64, and arm64 for the Steam Frame)
# exports, the Frame's Android APK and the Quest APK.
# Every release signs with the one key in $CAIRNFOLD_KEYSTORE ($CAIRNFOLD_KEYSTORE_PASS), so an installed APK updates in place.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
: "${CAIRNFOLD_KEYSTORE:?release.sh signs with \$CAIRNFOLD_KEYSTORE}" "${CAIRNFOLD_KEYSTORE_PASS:?}"
cd "$root"
. scripts/pins.sh
rev=$(git rev-parse HEAD)
tag=r$(build_number .)
git fetch -q origin
git merge-base --is-ancestor "$rev" origin/main || { echo "release: $rev is not on origin/main" >&2; exit 1; }
! gh release view "$tag" > /dev/null 2>&1 || { echo "release: $tag exists" >&2; exit 1; }
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for target in linux-x64 linux-arm64; do nix-shell --run "scripts/package.sh $target '$out/cairnfold-$target.tar.gz'"; done
nix-shell --run "scripts/package.sh windows '$out/cairnfold-windows.zip'"
for target in quest lepton; do nix-shell android.nix --run "scripts/android.sh $target '$out/cairnfold-$target.apk'"; done
gh release create "$tag" --target "$rev" --title "Cairnfold $tag" \
  --notes "Built from $rev. PC VR: cairnfold-windows.zip or cairnfold-linux-x64.tar.gz, run Cairnfold.exe or cairnfold/cairnfold with an OpenXR runtime (SteamVR). Steam Frame: cairnfold-lepton.apk for an Android depot, or cairnfold-linux-arm64.tar.gz (README, \"Running\"). Quest: install cairnfold-quest.apk (README, \"Quest\")." \
  "$out/cairnfold-quest.apk" "$out/cairnfold-lepton.apk" "$out/cairnfold-linux-x64.tar.gz" "$out/cairnfold-linux-arm64.tar.gz" "$out/cairnfold-windows.zip"
