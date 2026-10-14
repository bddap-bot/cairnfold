#!/usr/bin/env bash
# Builds the Quest APK (OpenXR through the vendors plugin's Meta loader) inside android.nix: android.sh OUT.apk
# Signs with $CAIRNFOLD_KEYSTORE (alias cairnfold, store and key password $CAIRNFOLD_KEYSTORE_PASS) when set, otherwise
# with a key generated once into the cache.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(realpath -m "$1")
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
unzip -q "$vendors" 'asset/addons/*' -d "$stage/vendors"
mv "$stage/vendors/asset/addons" "$stage/game/addons"
sed -i "s/^version\/code=.*/version\/code=$number/; s/^version\/name=.*/version\/name=\"$(git -C "$root" rev-parse --short HEAD)\"/" "$stage/game/export_presets.cfg"

if [ -z "${CAIRNFOLD_KEYSTORE:-}" ]; then
  CAIRNFOLD_KEYSTORE=$cache/local.keystore CAIRNFOLD_KEYSTORE_PASS=cairnfold
  [ -f "$CAIRNFOLD_KEYSTORE" ] || keytool -genkeypair -keystore "$CAIRNFOLD_KEYSTORE" -storepass "$CAIRNFOLD_KEYSTORE_PASS" \
    -alias cairnfold -keyalg RSA -keysize 2048 -validity 10000 -dname CN=Cairnfold
fi
[ -f "$CAIRNFOLD_KEYSTORE" ] || { echo "android: no keystore at $CAIRNFOLD_KEYSTORE" >&2; exit 1; }
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=$CAIRNFOLD_KEYSTORE GODOT_ANDROID_KEYSTORE_RELEASE_USER=cairnfold \
  GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=$CAIRNFOLD_KEYSTORE_PASS

cd "$stage/game"
# Install first so notices enter ordinary APK assets before signing.
mkdir -p android/build
unzip -q "$tdir/android_source.zip" -d android/build
printf '%s.stable\n' "$godot_version" > android/.build_version
touch android/build/.gdignore
"$root/scripts/notices.sh" quest "$stage/game/android/build/noticeAssets/notices"
cp "$root/scripts/android-notices.gradle" "$stage/game/android/build/"
printf '\napply from: "android-notices.gradle"\n' >> "$stage/game/android/build/build.gradle"
rm -f "$out"
if ! godot4 --headless --path . --export-release Quest "$out" > "$stage/export.log" 2>&1 || [ ! -f "$out" ]; then
  grep -v Fontconfig "$stage/export.log" | tail -60
  exit 1
fi

tools=$ANDROID_HOME/build-tools/$ANDROID_BUILD_TOOLS
"$tools/apksigner" verify "$out"
manifest=$("$tools/aapt" dump xmltree "$out" AndroidManifest.xml)
for want in org.khronos.openxr.intent.category.IMMERSIVE_HMD com.oculus.intent.category.VR android.hardware.vr.headtracking \
  android.hardware.vulkan.level org.khronos.openxr.permission.OPENXR; do
  grep -q "\"$want\"" <<<"$manifest" || { echo "android: manifest lacks $want" >&2; exit 1; }
done
unzip -l "$out" lib/arm64-v8a/libopenxr_loader.so > /dev/null || { echo "android: no OpenXR loader in the APK" >&2; exit 1; }
python3 "$root/scripts/notices.py" check "$out" "$stage/game/android/build/noticeAssets/notices"
echo "android: $out ($(git -C "$root" rev-parse --short HEAD)), signature and manifest verified"
