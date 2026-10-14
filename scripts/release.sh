#!/usr/bin/env bash
# Publishes HEAD as a GitHub release carrying every headset's build: the Steam Frame bundle and the Quest APK.
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
scripts/package.sh "$out/cairnfold-frame.tar.gz"
nix-shell android.nix --run "scripts/android.sh '$out/cairnfold-quest.apk'"
gh release create "$tag" --target "$rev" --title "Cairnfold $tag" \
  --notes "Built from $rev. Quest: install cairnfold-quest.apk (README, \"Quest\"). Steam Frame: cairnfold-frame.tar.gz through scripts/deploy.sh." \
  "$out/cairnfold-quest.apk" "$out/cairnfold-frame.tar.gz"
