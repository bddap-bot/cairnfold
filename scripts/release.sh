#!/usr/bin/env bash
# release.sh                publishes HEAD as a GitHub release carrying every build: Windows and Linux (x86_64, and
#                           arm64 for the Steam Frame) exports, the Frame's Android APK and the Quest APK. It becomes
#                           Latest only when HEAD is origin/main's tip, so publishing an older rev never takes it. With
#                           the store's secret in $meta_store (pins.sh), main's tip also goes to the Horizon Store's
#                           ALPHA channel as the store Quest APK.
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

case ${1:-} in
  --rollback) exec gh release edit "${2:?release: --rollback TAG}" --latest ;;
  --dry-run) dry=1 ;;
  '') dry= ;;
  *) echo "release: usage: release.sh [--dry-run | --rollback TAG]" >&2; exit 1 ;;
esac
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
store=$([ -f "$meta_store" ] && [ "$latest" = true ] && echo store || true)
# An APK signed by another key installs over no deployed copy, so every player would have to reinstall.
for build in quest lepton ${store:+quest:store}; do
  target=${build%:*} variant=${build#"$target"}
  apk=$out/cairnfold-$target${variant/:/-}.apk
  nix-shell android.nix --run "scripts/android.sh $target '$apk' ${variant#:}"
  signer=$(nix-shell android.nix --run "\"\$ANDROID_HOME/build-tools/\$ANDROID_BUILD_TOOLS/apksigner\" verify --print-certs '$apk'" |
    sed -n 's/^Signer #[0-9]* certificate SHA-256 digest: //p')
  [ "$signer" = "$android_cert_sha256" ] || { echo "release: $target APK signed by ${signer:-nothing}, not the deploying key $android_cert_sha256" >&2; exit 1; }
done
for target in linux-x64 linux-arm64; do nix-shell --run "scripts/package.sh $target '$out/cairnfold-$target.tar.gz'"; done
nix-shell --run "scripts/package.sh windows '$out/cairnfold-windows.zip'"
if [ -n "$dry" ]; then
  echo "release: dry run, $tag of $rev (Latest: $latest) built and checked, not published"
  exit 0
fi
assets=(cairnfold-quest.apk cairnfold-lepton.apk cairnfold-linux-x64.tar.gz cairnfold-linux-arm64.tar.gz cairnfold-windows.zip)
# Another run of this rev (a deploy job, the bothouse publisher) can publish $tag during the build; that run's release is
# this one's, so a complete one is success.
if ! gh release create "$tag" --target "$rev" --latest="$latest" --title "$(sed -n 's/^config\/name="\(.*\)"$/\1/p' game/project.godot) $tag" \
  --notes "Built from $rev. PC VR: cairnfold-windows.zip or cairnfold-linux-x64.tar.gz, run Cairnfold.exe or cairnfold/cairnfold with an OpenXR runtime (SteamVR). Steam Frame: cairnfold-lepton.apk for an Android depot, or cairnfold-linux-arm64.tar.gz (README, \"Running\"). Quest: install cairnfold-quest.apk (README, \"Quest\")." \
  "${assets[@]/#/$out/}"; then
  published=$(gh release view "$tag" --json targetCommitish,isDraft,assets --jq '[.targetCommitish, .isDraft, ([.assets[].name] | sort | join(" "))] | join(" ")' 2>&1) || true
  [ "$published" = "$rev false $(printf '%s\n' "${assets[@]}" | sort | paste -sd ' ')" ] ||
    { echo "release: $tag not created, and the existing one is not a complete release of $rev: $published" >&2; exit 1; }
  echo "release: $tag of $rev was published by another run; Latest is left as it is" >&2
  exit 0
fi
if [ -n "$store" ]; then
  util=$(fetch "${ovr_platform_util[@]}")
  chmod +x "$util"
  # The uploader takes its secret only on the command line: its --config reader rejects any file, and it reads no
  # environment.
  # shellcheck source=/dev/null
  (. "$meta_store"; "$util" upload-quest-build --app-id "$meta_app_id" --app-secret "$META_APP_SECRET" --channel ALPHA \
    --age-group TEENS_AND_ADULTS --apk "$out/cairnfold-quest-store.apk" --notes "$tag, built from $rev" \
    --disable-progress-bar --wait-for-postprocessing)
fi
