#!/usr/bin/env bash
# release.sh                publishes HEAD's builds, Latest only if its tag is the highest, so publish order never moves
#                           Latest back; main's tip as Latest also goes to the Horizon Store's ALPHA with $meta_store.
# release.sh --dry-run       builds and checks them, of any rev, publishing nothing.
# release.sh --rollback TAG  marks TAG Latest until a higher release.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/pins.sh

highest() {
  gh release list --exclude-drafts --limit 100000 --json tagName --jq \
    "[.[].tagName, \"$tag\" | select(test(\"^r[0-9]+$\")) | ltrimstr(\"r\") | tonumber] | max | \"r\(.)\""
}

# A draft is a create that failed past its own cleanup (a GitHub 500); counted as the release it would wedge main unreleased.
exists() {
  local draft
  draft=$(gh release view "$1" --json isDraft --jq .isDraft 2>&1) || {
    [ "$draft" = "release not found" ] || { echo "release: gh release view $1: $draft" >&2; exit 1; }
    return 1
  }
  [ "$draft" = true ] || return 0
  echo "release: deleting $1, a draft left by a failed create" >&2
  gh release delete "$1" --yes
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
if [ -z "$dry" ]; then
  git merge-base --is-ancestor "$rev" origin/main || { echo "release: $rev is not on origin/main" >&2; exit 1; }
  # After a rollback main's release exists and is not Latest; that is the state asked for, not a failure.
  ! exists "$tag" || { echo "release: $tag exists; Latest is left as it is" >&2; exit 0; }
fi
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
store=$([ -f "$meta_store" ] && [ "$rev" = "$(git rev-parse origin/main)" ] && echo store || true)
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
  echo "release: dry run, $tag of $rev built and checked, not published"
  exit 0
fi
top=$(highest)
latest=$([ "$top" = "$tag" ] && echo true || echo false)
assets=(cairnfold-quest.apk cairnfold-lepton.apk cairnfold-linux-x64.tar.gz cairnfold-linux-arm64.tar.gz cairnfold-windows.zip)
# Another run of this rev can publish $tag during the build, and a complete one is success; minutes of builds are worth
# a retried create.
tries=3
for try in $(seq "$tries"); do
  if gh release create "$tag" --target "$rev" --latest="$latest" --title "$(sed -n 's/^config\/name="\(.*\)"$/\1/p' game/project.godot) $tag" \
    --notes "Built from $rev. PC VR: cairnfold-windows.zip or cairnfold-linux-x64.tar.gz, run Cairnfold.exe or cairnfold/cairnfold with an OpenXR runtime (SteamVR). Steam Frame: cairnfold-lepton.apk for an Android depot, or cairnfold-linux-arm64.tar.gz (README, \"Running\"). Quest: install cairnfold-quest.apk (README, \"Quest\")." \
    "${assets[@]/#/$out/}"; then
    break
  fi
  published=$(gh release view "$tag" --json targetCommitish,isDraft,assets --jq '[.targetCommitish, .isDraft, ([.assets[].name] | sort | join(" "))] | join(" ")' 2>&1) || true
  if [ "$published" = "$rev false $(printf '%s\n' "${assets[@]}" | sort | paste -sd ' ')" ]; then
    echo "release: $tag of $rev was published by another run; Latest is left as it is" >&2
    exit 0
  fi
  [ "$try" != "$tries" ] || { echo "release: $tag not created, and the existing one is not a complete release of $rev: $published" >&2; exit 1; }
  echo "release: creating $tag failed ($published), trying again" >&2
  sleep $((try * 30))
done
# Each run follows every higher tag it sees, so of racing runs the last edit is the highest.
[ "$latest" = true ] || { echo "release: $tag published; $top is higher, so Latest is left as it is" >&2; exit 0; }
marked=$tag
while top=$(highest) && [ "$top" != "$marked" ]; do
  gh release edit "$top" --latest > /dev/null
  marked=$top
done
[ "$top" = "$marked" ] || exit 1
if [ "$marked" != "$tag" ]; then
  echo "release: $tag published; $marked, published meanwhile, is Latest" >&2
  exit 0
fi
if [ -n "$store" ]; then
  util=$(fetch "${ovr_platform_util[@]}")
  chmod +x "$util"
  # The uploader takes its secret only as an argument: its --config rejects any file, and it reads no environment.
  # Once $tag is Latest no later run of this rev reaches here, so a store-side processing failure is retried now.
  for try in 1 2 3; do
    # shellcheck source=/dev/null
    (. "$meta_store"; "$util" upload-quest-build --app-id "$meta_app_id" --app-secret "$META_APP_SECRET" --channel ALPHA \
      --age-group TEENS_AND_ADULTS --apk "$out/cairnfold-quest-store.apk" --notes "$tag, built from $rev" \
      --disable-progress-bar --wait-for-postprocessing) && exit 0
    [ "$try" != 3 ] || { echo "release: $tag published, but its store upload failed $try times" >&2; exit 1; }
    echo "release: store upload of $tag failed, trying again" >&2
    sleep $((try * 300))
  done
fi
