# shellcheck shell=bash disable=SC2034
# Sourced by the build scripts: every pinned download, and the fetch that verifies it.
godot_version=4.5.1
godot_release=https://github.com/godotengine/godot/releases/download/$godot_version-stable
godot_templates=("$godot_release/Godot_v$godot_version-stable_export_templates.tpz" 1998af37f1387684e2c211cdb483daf492fc64dc6b12096bddcdca25b6910c86)
openxr_vendors_version=4.3.1-stable
openxr_vendors=("https://github.com/GodotVR/godot_openxr_vendors/releases/download/$openxr_vendors_version/godotopenxrvendorsaddon.zip" 1620e9a589d205023e008ea27430843f5b8bb2690b62d08bd1fadc87c49b2e3e)
godot_source=("$godot_release/godot-$godot_version-stable.tar.xz" 559e11bdd85033640d49db67baa6f15be1128b2af38a5acc06e02b53363d8dde)
openxr_vendors_source=("https://codeload.github.com/GodotVR/godot_openxr_vendors/tar.gz/refs/tags/$openxr_vendors_version" c7536406d3d95f70807e20ef523b2b09ab13495faa393810a776e4dcfb1dde49)
# The godot-cpp submodule at the pinned vendors release.
godot_cpp_license=(https://raw.githubusercontent.com/godotengine/godot-cpp/269c925c2905b28c03921594d8d1e70cd4ba7beb/LICENSE.md 26a5b210d90760156ce886267ce9df235787dcc6cebfd7ecd95ef5b6fdcc95bf)
# What the official Windows template links beyond Godot's own sources: Mesa's NIR (through godot-nir-static, the
# version Godot's install_d3d12_sdk_windows.py names) and the MinGW-w64 runtime of its Fedora MinGW toolchain.
godot_nir_license=(https://raw.githubusercontent.com/godotengine/godot-nir-static/23.1.9-1/LICENSE.md 26a5b210d90760156ce886267ce9df235787dcc6cebfd7ecd95ef5b6fdcc95bf)
mesa_license=(https://gitlab.freedesktop.org/mesa/mesa/-/raw/52ab5584b870be041b93f702693ea3f5665df860/docs/license.rst a00275a53178e2645fb65be99a785c110513446a5071ff2c698ed260ad917d75)
mingw_license=(https://raw.githubusercontent.com/mingw-w64/mingw-w64/v12.0.0/COPYING.MinGW-w64-runtime/COPYING.MinGW-w64-runtime.txt e9b2dc02451ea29092a1f25fa0f3c07207ed421f1807dffb0c4e6dce69dee7bd)
# The Steam binding, only in Steam packages (docs/package-notices.md, "Steam packages"); never committed.
godotsteam_version=4.23
godotsteam=("https://codeberg.org/GodotSteam/GodotSteam/releases/download/v$godotsteam_version-gde/godotsteam-$godotsteam_version-gdextension-plugin-4.4.zip" c1728b4bf330da851a00eaf64dab2e99c506018b1d9f529511b25d7fe7649e97)
cinzel_license=(https://raw.githubusercontent.com/NDISCOVER/Cinzel/dd598495b0fb2ad84270d5cc75d642d2f1e8eabf/OFL.txt a46624198eeb4c2e442c38b0ff3bd8f52caeefd76675c36f410e2fb69014a239)
android_ndk_version=28.1.13356709
android_ndk_notice_sha256=faf0dc52cf6ce9ab09a04b0c074a378dd2565ee1ed9bc1179d83793bcdba012e
android_ndk_toolchain_sha256=789714a9076571c580cf531bdcebec776a4d889c12c3c1108adafc6e4338710a
cache=${XDG_CACHE_HOME:-$HOME/.cache}/nestcombe
mkdir -p "$cache"

# fetch URL SHA256: prints the cached path, downloading and verifying it first if needed.
fetch() {
  local file=$cache/${1##*/}
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
