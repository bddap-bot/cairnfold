#!/usr/bin/env bash
# Prints the path of an engine built from the pinned Godot source with engine.patch, every export's one renderer:
#   engine.sh linux-x64|linux-arm64|windows   the release export template, inside shell.nix
#   engine.sh android STOCK_AAR               the Android release library, inside android.nix: STOCK_AAR, the official
#                                             template's libs/release/godot-lib.template_release.aar, with its arm64
#                                             engine replaced
# Each builds with the official template's flags and NDK or Linux SDK (toolchains.nix), less AccessKit's static library
# (screen readers load it at run time) and on Windows ANGLE and Direct3D 12, and is cached under the hash of everything
# that goes into it.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scripts/pins.sh
. "$root/scripts/pins.sh"
target=$1
patch_file=$root/scripts/engine.patch
flags=(target=template_release production=yes debug_symbols=yes)
case $target in
  linux-x64) toolchain=$CAIRNFOLD_SDK_X64 strip=x86_64-godot-linux-gnu-strip flags+=(platform=linuxbsd arch=x86_64) built=godot.linuxbsd.template_release.x86_64 ;;
  linux-arm64) toolchain=$CAIRNFOLD_SDK_ARM64 strip=aarch64-godot-linux-gnu-strip flags+=(platform=linuxbsd arch=arm64) built=godot.linuxbsd.template_release.arm64 ;;
  windows)
    toolchain=$CAIRNFOLD_MINGW strip=x86_64-w64-mingw32-strip built=godot.windows.template_release.x86_64.llvm.exe
    # Direct3D 12 needs Mesa's NIR and Microsoft's SDKs, and the project renders through Vulkan, so a machine without
    # Vulkan falls back to OpenGL. llvm-mingw is the official Windows arm64 toolchain; nixpkgs' GCC MinGW threads
    # through mcfgthread, a runtime no official template links.
    flags+=(platform=windows arch=x86_64 use_mingw=yes use_llvm=yes d3d12=no) ;;
  android)
    stock=$(realpath "$2")
    toolchain=$ANDROID_HOME/ndk/$android_ndk_version
    flags+=(platform=android arch=arm64 swappy=yes) ;;
  *) echo "engine: no target $target" >&2; exit 1 ;;
esac
key=$(cat "$0" "$patch_file" ${stock:+"$stock"} <(printf '%s\n' "${godot_source[1]}" "${godot_swappy[1]}" \
  "$(realpath "$toolchain")" "$(realpath "$(command -v scons)")" \
  "$(command -v wayland-scanner | xargs -r realpath)" "${flags[@]}") | sha256sum | cut -d' ' -f1)
dir=$cache/engine
out=$dir/$target-$key
if [ -f "$out" ]; then
  echo "engine: cached $out" >&2
  echo "$out"
  exit 0
fi

mkdir -p "$dir"
work=$(mktemp -d "$dir/build.XXXXXX")
log=$out.log
echo "engine: building $target-$key, log in $log" >&2
exec 3>&1 4>&2 > "$log" 2>&1
trap '[ $? = 0 ] || tail -60 "$log" >&4; rm -rf "$work"' EXIT
tar -xJf "$(fetch "${godot_source[@]}")" -C "$work"
src=$work/godot-$godot_version-stable
patch -d "$src" -p1 --forward --batch < "$patch_file"
if [ "$target" = android ]; then
  # detect.py refuses swappy=yes unless the static library exists for all four ABIs.
  for abi in arm64-v8a armeabi-v7a x86 x86_64; do
    unzip -q -o "$(fetch "${godot_swappy[@]}")" "$abi/libswappy_static.a" -d "$src/thirdparty/swappy-frame-pacing"
  done
fi
(
  cd "$src"
  unset SCONS_CACHE
  case $target in
    linux-*) PATH=$toolchain/bin:$PATH ;;
    # Godot finds MinGW only through MINGW_PREFIX when it lists the platforms it can build.
    windows) export MINGW_PREFIX=$toolchain ;;
    android) export ANDROID_NDK_ROOT=$toolchain ;;
  esac
  SCONSFLAGS='' scons -j"$(nproc)" "${flags[@]}"
)
case $target in
  linux-*|windows) "$toolchain/bin/$strip" --strip-unneeded -o "$work/out" "$src/bin/$built" ;;
  android)
    "$toolchain/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" --strip-unneeded -o "$work/engine.so" \
      "$src/platform/android/java/lib/libs/release/arm64-v8a/libgodot_android.so"
    python3 - "$stock" "$work/engine.so" "$work/out" jni/arm64-v8a/libgodot_android.so << 'EOF'
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
    ;;
esac
mv "$work/out" "$out"
echo "$out" >&3
