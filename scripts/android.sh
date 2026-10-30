#!/usr/bin/env bash
# Builds an APK inside android.nix: android.sh quest|lepton OUT.apk [store|steam]
#   quest   the Quest build, OpenXR through the vendors plugin's Meta flavor; a store Quest APK, the one the Horizon Store
#           gets, also carries the Platform SDK and the app's id, and quits for a user who does not own the game (Store)
#   lepton  the Steam Frame's Android build, run by its Lepton container, through the Khronos flavor: no Meta SDK
#           material enters it, so the Meta SDK's approved-product terms stay off a Steam product
# Both carry the engine scripts/engine.sh builds.
# A steam Lepton APK also carries the GodotSteam extension and Valve's steam_api library; a Quest APK never does.
# Every APK, bench or release, signs with the one key in $CAIRNFOLD_ANDROID_KEY (AGENTS.md, "Signing"), so any build
# installs over any other and the garden on the device survives.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
target=$1
case $target in quest) preset=Quest ;; lepton) preset=Lepton ;; *) echo "android: target is quest or lepton" >&2; exit 1 ;; esac
out=$(realpath -m "$2")
variant=${3:-}
case $target:$variant in quest:|quest:store|lepton:|lepton:steam) ;; *) echo "android: store is a quest variant, steam a lepton one" >&2; exit 1 ;; esac
steam=${variant#store}
steam_dir=androidarm64
# shellcheck source=scripts/stage.sh
. "$root/scripts/stage.sh"
unzip -p "$(fetch "${godot_templates[@]}")" templates/android_source.zip > "$tdir/android_source.zip"
vendors=$(fetch "${openxr_vendors[@]}")
number=$(build_number "$root")
# A Gradle daemon outlives its export by its 3 h default idle timeout, holding a worker's RAM; a minute still serves
# back-to-back exports, which a single-use JVM per export would double. The daemon lives in the cgroup of the export
# that spawned it and dies with it, so only exports in that cgroup may reuse it: a daemon a finished job left was
# killed mid-export under the packaging service.
daemons=$cache/gradle/daemons/$(cksum < /proc/self/cgroup | cut -d' ' -f1)
export GRADLE_USER_HOME=$cache/gradle GRADLE_OPTS="-Dorg.gradle.daemon.idletimeout=60000 -Dorg.gradle.daemon.registry.base=$daemons"

unzip -q "$vendors" 'asset/addons/*' -d "$stage/vendors"
# A steam build's GodotSteam is already in the game's addons.
cp -r "$stage/vendors/asset/addons" "$stage/game/"
if [ "$target" = lepton ]; then
  find "$stage/game/addons/godotopenxrvendors/.bin/android" -name '*.aar' ! -name 'godotopenxr-khronos-*' -delete
fi
if [ "$variant" = store ]; then
  printf '[gd_resource type="Resource" format=3]\n[resource]\nmetadata/app_id = "%s"\n' "$meta_app_id" > "$stage/game/store.tres"
fi
sed -i "s/^version\/code=.*/version\/code=$number/; s/^version\/name=.*/version\/name=\"$(git -C "$root" rev-parse --short HEAD)\"/" "$stage/game/export_presets.cfg"
# Only our own headsets take performances (PlayLog.ARM); an APK a store sells declares no microphone.
[ -z "$variant" ] || sed -i '/^permissions\/record_audio=/d' "$stage/game/export_presets.cfg"

[ -f "$android_key/release.keystore" ] || { echo "android: no signing key in $android_key (AGENTS.md, \"Signing\")" >&2; exit 1; }
password=$(< "$android_key/password")
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=$android_key/release.keystore GODOT_ANDROID_KEYSTORE_RELEASE_USER=cairnfold \
  GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=$password

cd "$stage/game"
# Install first so notices enter ordinary APK assets before signing.
mkdir -p android/build
unzip -q "$tdir/android_source.zip" -d android/build
# The engine build (scons) and the export (Gradle) size themselves to every CPU; with-jobs holds them to their share.
cp "$("$root/scripts/with-jobs" "$root/scripts/engine.sh" android android/build/libs/release/godot-lib.template_release.aar)" \
  android/build/libs/release/godot-lib.template_release.aar
printf '%s.stable\n' "$godot_version" > android/.build_version
# The toolkit's Android library brings its own GDExtension and the Platform SDK loader. Its addon is left out: the
# addon's editor library crashes Godot 4.6 on every cold import.
if [ "$variant" = store ]; then
  unzip -q -j "$(fetch "${meta_toolkit[@]}")" asset/addons/godot_meta_toolkit/.bin/android/release/godot_meta_toolkit-release.aar \
    -d android/build/libs/release
fi
touch android/build/.gdignore
# The vendors plugin declares head tracking optional; the Horizon Store requires an immersive app to require it.
if [ "$target" = quest ]; then
  sed -i 's|^\( *\)<application|\1<uses-feature tools:node="replace" android:name="android.hardware.vr.headtracking" android:required="true" android:version="1" />\n&|' \
    android/build/src/main/AndroidManifest.xml
fi
"$root/scripts/notices.sh" "$target" "$stage/game/android/build/noticeAssets/notices" "$variant"
cp "$root/scripts/android-notices.gradle" "$stage/game/android/build/"
printf '\napply from: "android-notices.gradle"\n' >> "$stage/game/android/build/build.gradle"
rm -f "$out"
"$root/scripts/with-jobs" "$root/scripts/export.sh" . "$preset" "$out" "$stage/export.log"

tools=$ANDROID_HOME/build-tools/$ANDROID_BUILD_TOOLS
"$tools/apksigner" verify "$out"
manifest=$("$tools/aapt" dump xmltree "$out" AndroidManifest.xml)
wants=(org.khronos.openxr.intent.category.IMMERSIVE_HMD android.hardware.vr.headtracking android.hardware.vulkan.level
  org.khronos.openxr.permission.OPENXR android.permission.INTERNET)
[ "$target" = lepton ] || wants+=(com.oculus.intent.category.VR oculus.software.handtracking com.oculus.ossplash)
for want in "${wants[@]}"; do
  grep -q "\"$want\"" <<<"$manifest" || { echo "android: manifest lacks $want" >&2; exit 1; }
done
# Lepton's target SDK 32 has no reason of its own: its preset copied the Quest's, which went to 34 for the Horizon
# Store (5e71dfb1) after the copy. Raising it is a change to check on the Frame.
if [ "$target" = quest ]; then
  attribute() { awk -v n="$1" -v a="$2" '$0 ~ n { f = 1 } f && $0 ~ a { sub(/.*\)/, ""); print; exit }' <<<"$manifest"; }
  [ "$(attribute '"android.hardware.vr.headtracking"' android:required)" = 0xffffffff ] || { echo "android: the Quest manifest does not require head tracking" >&2; exit 1; }
  [ "$(attribute uses-sdk android:targetSdkVersion)" = 0x22 ] || { echo "android: the Quest manifest does not target SDK 34" >&2; exit 1; }
fi
if [ "$target" = lepton ] && grep -q -i -E 'oculus|horizonos|com\.meta\.' <<<"$manifest"; then
  echo "android: the Lepton manifest names Meta" >&2
  exit 1
fi
microphone=$(grep -c 'android.permission.RECORD_AUDIO' <<<"$manifest" || true)
[ "$microphone" -eq "$([ -z "$variant" ] && echo 1 || echo 0)" ] || { echo "android: a ${variant:-plain} APK declaring the microphone $microphone times" >&2; exit 1; }
unzip -l "$out" lib/arm64-v8a/libopenxr_loader.so > /dev/null || { echo "android: no OpenXR loader in the APK" >&2; exit 1; }
[ "$target" = lepton ] || unzip -l "$out" assets/vr_splash.png > /dev/null || { echo "android: no system splash in the Quest APK" >&2; exit 1; }
steamed=$(unzip -Z1 "$out" | grep -c -E 'lib/arm64-v8a/lib(godotsteam|steam_api)' || true)
[ "$steamed" -eq $((${#steam} ? 2 : 0)) ] || { echo "android: $steamed Steam libraries in a ${steam:-plain} APK" >&2; exit 1; }
platform=$(unzip -Z1 "$out" | grep -c -E 'lib/arm64-v8a/lib(ovrplatformloader|godot_meta_toolkit)\.so' || true)
[ "$platform" -eq "$([ "$variant" = store ] && echo 2 || echo 0)" ] || { echo "android: $platform Platform SDK libraries in a ${variant:-plain} APK" >&2; exit 1; }
python3 "$root/scripts/notices.py" check "$out" "$stage/game/android/build/noticeAssets/notices"
echo "android: $out ($(git -C "$root" rev-parse --short HEAD)), signature and manifest verified"
