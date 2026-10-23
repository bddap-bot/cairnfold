#!/usr/bin/env bash
# release.sh                publishes HEAD as a GitHub release carrying every build: Windows and Linux (x86_64, and
#                           arm64 for the Steam Frame) exports, the Frame's Android APK and the Quest APK. It becomes
#                           Latest only when HEAD is origin/main's tip, so publishing an older rev never takes it.
# release.sh --dry-run       builds and checks every build release.sh would publish, of any rev, and publishes nothing.
# release.sh --rollback TAG  marks the published release TAG Latest, the way back to a build; the next release of
#                           origin/main's tip takes Latest again.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
. scripts/pins.sh

# exists TAG: whether release TAG is published; any failure other than its absence stops the run.
exists() {
  local err
  err=$(gh release view "$1" 2>&1 > /dev/null) && return 0
  [ "$err" = "release not found" ] || { echo "release: gh release view $1: $err" >&2; exit 1; }
  return 1
}

if [ "${1:-}" = --rollback ]; then
  exists "${2:?release: --rollback TAG}" || { echo "release: no release $2" >&2; exit 1; }
  gh release edit "$2" --latest
  exit 0
fi
dry=$([ "${1:-}" = --dry-run ] && echo 1 || true)
rev=$(git rev-parse HEAD)
tag=r$(build_number .)
git fetch -q origin
latest=$([ "$rev" = "$(git rev-parse origin/main)" ] && echo true || echo false)
if [ -z "$dry" ]; then
  git merge-base --is-ancestor "$rev" origin/main || { echo "release: $rev is not on origin/main" >&2; exit 1; }
  # After a rollback main's release exists and is not Latest; that is the state asked for, not a failure.
  ! exists "$tag" || { echo "release: $tag exists; Latest is left as it is" >&2; exit 0; }
fi
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
# An APK signed by another key installs over no deployed copy, so every player would have to reinstall.
for target in quest lepton; do
  apk=$out/nestcombe-$target.apk
  nix-shell android.nix --run "scripts/android.sh $target '$apk'"
  signer=$(nix-shell android.nix --run "\"\$ANDROID_HOME/build-tools/\$ANDROID_BUILD_TOOLS/apksigner\" verify --print-certs '$apk'" |
    sed -n 's/^Signer #[0-9]* certificate SHA-256 digest: //p')
  [ "$signer" = "$android_cert_sha256" ] || { echo "release: $target APK signed by ${signer:-nothing}, not the deploying key $android_cert_sha256" >&2; exit 1; }
done
for target in linux-x64 linux-arm64; do nix-shell --run "scripts/package.sh $target '$out/nestcombe-$target.tar.gz'"; done
nix-shell --run "scripts/package.sh windows '$out/nestcombe-windows.zip'"
if [ -n "$dry" ]; then
  echo "release: dry run, $tag of $rev (Latest: $latest) built and checked, not published"
  exit 0
fi
gh release create "$tag" --target "$rev" --latest="$latest" --title "$(sed -n 's/^config\/name="\(.*\)"$/\1/p' game/project.godot) $tag" \
  --notes "Built from $rev. PC VR: nestcombe-windows.zip or nestcombe-linux-x64.tar.gz, run Nestcombe.exe or nestcombe/nestcombe with an OpenXR runtime (SteamVR). Steam Frame: nestcombe-lepton.apk for an Android depot, or nestcombe-linux-arm64.tar.gz (README, \"Running\"). Quest: install nestcombe-quest.apk (README, \"Quest\")." \
  "$out/nestcombe-quest.apk" "$out/nestcombe-lepton.apk" "$out/nestcombe-linux-x64.tar.gz" "$out/nestcombe-linux-arm64.tar.gz" "$out/nestcombe-windows.zip"
