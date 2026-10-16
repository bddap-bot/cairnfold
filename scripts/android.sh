#!/usr/bin/env bash
# Builds an APK inside android.nix: android.sh quest|lepton OUT.apk [steam]
#   quest   the Quest build, OpenXR through the vendors plugin's Meta flavor
#   lepton  the Steam Frame's Android build, run by its Lepton container, through the Khronos flavor: no Meta SDK
#           material enters it, so the Meta SDK's approved-product terms stay off a Steam product
# A steam Lepton APK also carries the GodotSteam extension and Valve's steam_api library; a Quest APK never does.
# Every APK, bench or release, signs with the one key in $NESTCOMBE_ANDROID_KEY (AGENTS.md, "Signing"), so any build
# installs over any other and the garden on the device survives.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
target=$1
case $target in quest) preset=Quest ;; lepton) preset=Lepton ;; *) echo "android: target is quest or lepton" >&2; exit 1 ;; esac
out=$(realpath -m "$2")
steam=${3:-}
case $target:$steam in quest:|lepton:|lepton:steam) ;; *) echo "android: steam is a lepton variant only" >&2; exit 1 ;; esac
. "$root/scripts/pins.sh"
case $(godot4 --version) in "$godot_version".stable*) ;; *) echo "android: godot4 is not $godot_version" >&2; exit 1 ;; esac
templates=$(fetch "${godot_templates[@]}")
vendors=$(fetch "${openxr_vendors[@]}")
number=$(build_number "$root")

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
export XDG_DATA_HOME=$stage/data XDG_CONFIG_HOME=$stage/config GRADLE_USER_HOME=$cache/gradle
tdir=$XDG_DATA_HOME/godot/export_templates/$godot_version.stable
mkdir -p "$tdir"
unzip -p "$templates" templates/android_source.zip > "$tdir/android_source.zip"
echo "$godot_version.stable" > "$tdir/version.txt"

git -C "$root" archive HEAD game | tar -x -C "$stage"
printf '[gd_resource type="Resource" format=3]\n[resource]\nmetadata/revision = "%s"\n' "$(git -C "$root" rev-parse HEAD)" > "$stage/game/revision.tres"
unzip -q "$vendors" 'asset/addons/*' -d "$stage/vendors"
mv "$stage/vendors/asset/addons" "$stage/game/addons"
if [ "$target" = lepton ]; then
  find "$stage/game/addons/godotopenxrvendors/.bin/android" -name '*.aar' ! -name 'godotopenxr-khronos-*' -delete
fi
if [ -n "$steam" ]; then
  unzip -q "$(fetch "${godotsteam[@]}")" addons/godotsteam/godotsteam.gdextension 'addons/godotsteam/androidarm64/*' -d "$stage/game"
fi
sed -i "s/^version\/code=.*/version\/code=$number/; s/^version\/name=.*/version\/name=\"$(git -C "$root" rev-parse --short HEAD)\"/" "$stage/game/export_presets.cfg"

[ -f "$android_key/release.keystore" ] || { echo "android: no signing key in $android_key (AGENTS.md, \"Signing\")" >&2; exit 1; }
password=$(< "$android_key/password")
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=$android_key/release.keystore GODOT_ANDROID_KEYSTORE_RELEASE_USER=nestcombe \
  GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=$password

cd "$stage/game"
# Install first so notices enter ordinary APK assets before signing.
mkdir -p android/build
unzip -q "$tdir/android_source.zip" -d android/build
printf '%s.stable\n' "$godot_version" > android/.build_version
touch android/build/.gdignore
"$root/scripts/notices.sh" "$target" "$stage/game/android/build/noticeAssets/notices" "$steam"
cp "$root/scripts/android-notices.gradle" "$stage/game/android/build/"
printf '\napply from: "android-notices.gradle"\n' >> "$stage/game/android/build/build.gradle"
rm -f "$out"
if ! godot4 --headless --path . --export-release "$preset" "$out" > "$stage/export.log" 2>&1 || [ ! -f "$out" ]; then
  grep -v Fontconfig "$stage/export.log" | tail -60
  exit 1
fi

tools=$ANDROID_HOME/build-tools/$ANDROID_BUILD_TOOLS
"$tools/apksigner" verify "$out"
manifest=$("$tools/aapt" dump xmltree "$out" AndroidManifest.xml)
wants=(org.khronos.openxr.intent.category.IMMERSIVE_HMD android.hardware.vr.headtracking android.hardware.vulkan.level
  org.khronos.openxr.permission.OPENXR android.permission.INTERNET)
[ "$target" = lepton ] || wants+=(com.oculus.intent.category.VR oculus.software.handtracking)
for want in "${wants[@]}"; do
  grep -q "\"$want\"" <<<"$manifest" || { echo "android: manifest lacks $want" >&2; exit 1; }
done
if [ "$target" = lepton ] && grep -q -i -E 'oculus|horizonos|com\.meta\.' <<<"$manifest"; then
  echo "android: the Lepton manifest names Meta" >&2
  exit 1
fi
unzip -l "$out" lib/arm64-v8a/libopenxr_loader.so > /dev/null || { echo "android: no OpenXR loader in the APK" >&2; exit 1; }
steamed=$(unzip -Z1 "$out" | grep -c -E 'lib/arm64-v8a/lib(godotsteam|steam_api)' || true)
[ "$steamed" -eq $((${#steam} ? 2 : 0)) ] || { echo "android: $steamed Steam libraries in a ${steam:-plain} APK" >&2; exit 1; }
python3 "$root/scripts/notices.py" check "$out" "$stage/game/android/build/noticeAssets/notices"
echo "android: $out ($(git -C "$root" rev-parse --short HEAD)), signature and manifest verified"
