#!/usr/bin/env bash
# Collect unchanged upstream notices using the same pins as the binaries: notices.sh linux-x64|linux-arm64|windows|quest|lepton DIRECTORY [steam|store]
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/scripts/pins.sh"
kind=$1
out=$2
case "$kind" in linux-x64|linux-arm64|windows|quest|lepton) ;; *) exit 1 ;; esac
mkdir -p "$out"
cp "$root"/LICENSE-* "$out/"
cp "$root/docs/package-notices.md" "$out/README.md"
ndk=()
case $kind in quest|lepton) ndk=("$android_ndk_version") ;; esac
python3 "$root/scripts/notices.py" extract "$(fetch "${godot_source[@]}")" "$out/godot" "${ndk[@]}"
cp "$(fetch "${cinzel_license[@]}")" "$out/Cinzel-OFL.txt"
printf 'Godot %s\n%s\nSHA256 %s\nCinzel OFL\n%s\nSHA256 %s\n' \
  "$godot_version" "${godot_source[@]}" "${cinzel_license[@]}" > "$out/SOURCES.txt"
if [ "${3:-}" = steam ]; then
  mkdir -p "$out/godotsteam"
  unzip -p "$(fetch "${godotsteam[@]}")" addons/godotsteam/license.md > "$out/godotsteam/license.md"
  printf 'GodotSteam %s\n%s\nSHA256 %s\n' "$godotsteam_version" "${godotsteam[@]}" >> "$out/SOURCES.txt"
fi
if [ "${3:-}" = store ]; then
  mkdir -p "$out/godot-meta-toolkit"
  cp "$(fetch "${meta_toolkit_license[@]}")" "$out/godot-meta-toolkit/LICENSE.txt"
  printf 'Godot Meta Toolkit %s\n%s\nSHA256 %s\nLicense\n%s\nSHA256 %s\n' \
    "$meta_toolkit_version" "${meta_toolkit[@]}" "${meta_toolkit_license[@]}" >> "$out/SOURCES.txt"
fi
if [ "$kind" = windows ]; then
  mkdir -p "$out/windows"
  cp "$(fetch "${godot_nir_license[@]}")" "$out/windows/godot-nir-static-LICENSE.md"
  cp "$(fetch "${mesa_license[@]}")" "$out/windows/mesa-license.rst"
  cp "$(fetch "${mingw_license[@]}")" "$out/windows/COPYING.MinGW-w64-runtime.txt"
  printf 'Godot NIR static\n%s\nSHA256 %s\nMesa\n%s\nSHA256 %s\nMinGW-w64 runtime\n%s\nSHA256 %s\n' \
    "${godot_nir_license[@]}" "${mesa_license[@]}" "${mingw_license[@]}" >> "$out/SOURCES.txt"
fi
if [ "$kind" = quest ] || [ "$kind" = lepton ]; then
  python3 "$root/scripts/notices.py" extract "$(fetch "${openxr_vendors_source[@]}")" "$out/openxr-vendors" "$android_ndk_version"
  echo "$android_ndk_notice_sha256  $root/third_party/android-ndk/NOTICE" | sha256sum -c --quiet
  echo "$android_ndk_toolchain_sha256  $root/third_party/android-ndk/NOTICE.toolchain" | sha256sum -c --quiet
  cp -r "$root/third_party/android-ndk" "$out/"
  vendors=$(fetch "${openxr_vendors[@]}")
  if [ "$kind" = quest ]; then
    mkdir -p "$out/openxr-vendors/meta"
    for name in LICENSE-LOADER LICENSE-SDK; do
      unzip -p "$vendors" "asset/addons/godotopenxrvendors/meta/$name" > "$out/openxr-vendors/meta/$name"
    done
    printf 'Copyright © Meta Platform Technologies, LLC and its affiliates. All rights reserved.\n' > "$out/openxr-vendors/meta/NOTICE.txt"
  else
    mkdir -p "$out/openxr-vendors/khronos"
    unzip -p "$vendors" asset/addons/godotopenxrvendors/khronos/LICENSE > "$out/openxr-vendors/khronos/LICENSE"
  fi
  cp "$(fetch "${godot_cpp_license[@]}")" "$out/openxr-vendors/godot-cpp-LICENSE.md"
  printf 'OpenXR Vendors %s\n%s\nSHA256 %s\nSources\n%s\nSHA256 %s\nGodot C++ bindings license\n%s\nSHA256 %s\n' \
    "$openxr_vendors_version" "${openxr_vendors[@]}" "${openxr_vendors_source[@]}" "${godot_cpp_license[@]}" >> "$out/SOURCES.txt"
fi
