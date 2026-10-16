# shellcheck shell=bash disable=SC2034
# Sourced by the build scripts: every pinned download, and the fetch that verifies it.
godot_version=4.6
godot_release=https://github.com/godotengine/godot/releases/download/$godot_version-stable
godot_templates=("$godot_release/Godot_v$godot_version-stable_export_templates.tpz" 3b30ac8c1772f25f5dfa5f65922cab0a90e7b960176891237c5772515ebccc46)
openxr_vendors_version=5.1.0-stable
openxr_vendors=("https://github.com/GodotVR/godot_openxr_vendors/releases/download/$openxr_vendors_version/godotopenxrvendorsaddon.zip" 6a838dbdf4115549e4511ebee0da9a5dcc8f9f6258d4cc2f2ee57a907a3e2911)
godot_source=("$godot_release/godot-$godot_version-stable.tar.xz" 900ad0f6241b8051daa569cee1b07b6e30c4cb4f804471f72256d052334c0550)
openxr_vendors_source=("https://codeload.github.com/GodotVR/godot_openxr_vendors/tar.gz/refs/tags/$openxr_vendors_version" 60199880ae0eb06565979865f55969f5059cc088c8a7a5065366e2f90bce9653)
# The godot-cpp submodule at the pinned vendors release.
godot_cpp_license=(https://raw.githubusercontent.com/godotengine/godot-cpp/58d1de720b8ffe9f8ffcdfe3a85148582cfd2e74/LICENSE.md 26a5b210d90760156ce886267ce9df235787dcc6cebfd7ecd95ef5b6fdcc95bf)
# What the official Windows template links beyond Godot's own sources: Mesa's NIR (through godot-nir-static, the
# version Godot's install_d3d12_sdk_windows.py names) and the MinGW-w64 runtime of its Fedora MinGW toolchain.
godot_nir_license=(https://raw.githubusercontent.com/godotengine/godot-nir-static/25.3.1-1/LICENSE.md 26a5b210d90760156ce886267ce9df235787dcc6cebfd7ecd95ef5b6fdcc95bf)
mesa_license=(https://gitlab.freedesktop.org/mesa/mesa/-/raw/5005a50879b11b953ade113fccd13a208f706ba0/docs/license.rst 0d1a0472ecc81830e75c20d59b0ea02841e3db21255e0ebad97ab682c54d6615)
mingw_license=(https://raw.githubusercontent.com/mingw-w64/mingw-w64/v13.0.0/COPYING.MinGW-w64-runtime/COPYING.MinGW-w64-runtime.txt e9b2dc02451ea29092a1f25fa0f3c07207ed421f1807dffb0c4e6dce69dee7bd)
# The Steam binding, only in Steam packages (docs/package-notices.md, "Steam packages"); never committed.
godotsteam_version=4.23
godotsteam=("https://codeberg.org/GodotSteam/GodotSteam/releases/download/v$godotsteam_version-gde/godotsteam-$godotsteam_version-gdextension-plugin-4.4.zip" c1728b4bf330da851a00eaf64dab2e99c506018b1d9f529511b25d7fe7649e97)
cinzel_license=(https://raw.githubusercontent.com/NDISCOVER/Cinzel/dd598495b0fb2ad84270d5cc75d642d2f1e8eabf/OFL.txt a46624198eeb4c2e442c38b0ff3bd8f52caeefd76675c36f410e2fb69014a239)
android_ndk_version=28.1.13356709
android_ndk_notice_sha256=faf0dc52cf6ce9ab09a04b0c074a378dd2565ee1ed9bc1179d83793bcdba012e
android_ndk_toolchain_sha256=789714a9076571c580cf531bdcebec776a4d889c12c3c1108adafc6e4338710a
cache=${XDG_CACHE_HOME:-$HOME/.cache}/nestcombe
mkdir -p "$cache"
android_key=${NESTCOMBE_ANDROID_KEY:-${XDG_CONFIG_HOME:-$HOME/.config}/nestcombe/android-key}

# fetch URL SHA256: prints the cached path, downloading and verifying it first if needed.
fetch() {
  local file=$cache/$2-${1##*/}
  if ! { [ -f "$file" ] && echo "$2  $file" | sha256sum -c --quiet; }; then
    curl -fsSL --max-time 1800 -o "$file.part" "$1" &&
      echo "$2  $file.part" | sha256sum -c --quiet &&
      mv "$file.part" "$file" || return 1
  fi
  echo "$file"
}

# The commit count numbers builds and releases; a shallow clone would undercount it.
build_number() {
  [ "$(git -C "$1" rev-parse --is-shallow-repository)" = false ] || { echo "build: shallow clone, fetch --unshallow first" >&2; return 1; }
  git -C "$1" rev-list --count HEAD
}
