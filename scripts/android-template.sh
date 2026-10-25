#!/usr/bin/env bash
# Prints the path of the Android release library the APKs build from, inside android.nix: android-template.sh STOCK_AAR
# STOCK_AAR is the official template's libs/release/godot-lib.template_release.aar. Its arm64 engine is replaced by one
# built from the pinned Godot source with android-template.patch, with the official template's flags and NDK, and the
# result is cached under the hash of everything that goes into it.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scripts/pins.sh
. "$root/scripts/pins.sh"
stock=$(realpath "$1")
patch_file=$root/scripts/android-template.patch
ndk=$ANDROID_HOME/ndk/$android_ndk_version
entry=jni/arm64-v8a/libgodot_android.so

key=$(cat "$0" "$patch_file" "$stock" <(printf '%s\n' "${godot_source[1]}" "${godot_swappy[1]}" \
  "$(realpath "$ndk")" "$(realpath "$(command -v scons)")") | sha256sum | cut -d' ' -f1)
dir=$cache/android-template
aar=$dir/$key.aar
if [ -f "$aar" ]; then
  echo "android-template: cached $aar" >&2
  echo "$aar"
  exit 0
fi

mkdir -p "$dir"
work=$(mktemp -d "$dir/build.XXXXXX")
log=$dir/$key.log
echo "android-template: building $key, log in $log" >&2
exec 3>&1 4>&2 > "$log" 2>&1
trap '[ $? = 0 ] || tail -60 "$log" >&4; rm -rf "$work"' EXIT
tar -xJf "$(fetch "${godot_source[@]}")" -C "$work"
src=$work/godot-$godot_version-stable
patch -d "$src" -p1 --forward --batch < "$patch_file"
# detect.py refuses swappy=yes unless the static library exists for all four ABIs.
for abi in arm64-v8a armeabi-v7a x86 x86_64; do
  unzip -q -o "$(fetch "${godot_swappy[@]}")" "$abi/libswappy_static.a" -d "$src/thirdparty/swappy-frame-pacing"
done
(
  cd "$src"
  unset SCONS_CACHE
  ANDROID_NDK_ROOT=$ndk SCONSFLAGS='' scons -j"$(nproc)" platform=android target=template_release arch=arm64 \
    production=yes swappy=yes debug_symbols=yes
)
"$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" --strip-unneeded -o "$work/engine.so" \
  "$src/platform/android/java/lib/libs/release/arm64-v8a/libgodot_android.so"
python3 - "$stock" "$work/engine.so" "$work/out.aar" "$entry" << 'EOF'
import sys, zipfile
src, so, dst, entry = sys.argv[1:5]
with zipfile.ZipFile(src) as zin, zipfile.ZipFile(dst, "w") as zout:
    if entry not in zin.namelist():
        sys.exit(f"{src}: no {entry}")
    for info in zin.infolist():
        if info.filename == entry:
            with open(so, "rb") as f:
                zout.writestr(info, f.read(), compress_type=zipfile.ZIP_DEFLATED)
        else:
            zout.writestr(info, zin.read(info), compress_type=info.compress_type)
EOF
mv "$work/out.aar" "$aar"
echo "$aar" >&3
