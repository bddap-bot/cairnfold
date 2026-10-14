# shellcheck shell=bash disable=SC2034
# Sourced by the build scripts: every pinned download, and the fetch that verifies it.
godot_version=4.5.1
godot_release=https://github.com/godotengine/godot/releases/download/$godot_version-stable
godot_arm64=("$godot_release/Godot_v$godot_version-stable_linux.arm64.zip" 4a2c6bd5066aca9d207c75f540645e29272b129f2cf321d8ba30d922af11b00f)
godot_templates=("$godot_release/Godot_v$godot_version-stable_export_templates.tpz" 1998af37f1387684e2c211cdb483daf492fc64dc6b12096bddcdca25b6910c86)
openxr_vendors_version=4.3.1-stable
openxr_vendors=("https://github.com/GodotVR/godot_openxr_vendors/releases/download/$openxr_vendors_version/godotopenxrvendorsaddon.zip" 1620e9a589d205023e008ea27430843f5b8bb2690b62d08bd1fadc87c49b2e3e)
godot_source=("$godot_release/godot-$godot_version-stable.tar.xz" 559e11bdd85033640d49db67baa6f15be1128b2af38a5acc06e02b53363d8dde)
openxr_vendors_source=("https://codeload.github.com/GodotVR/godot_openxr_vendors/tar.gz/refs/tags/$openxr_vendors_version" c7536406d3d95f70807e20ef523b2b09ab13495faa393810a776e4dcfb1dde49)
# The godot-cpp submodule at the pinned vendors release.
godot_cpp_license=(https://raw.githubusercontent.com/godotengine/godot-cpp/269c925c2905b28c03921594d8d1e70cd4ba7beb/LICENSE.md 26a5b210d90760156ce886267ce9df235787dcc6cebfd7ecd95ef5b6fdcc95bf)
cinzel_license=(https://raw.githubusercontent.com/NDISCOVER/Cinzel/dd598495b0fb2ad84270d5cc75d642d2f1e8eabf/OFL.txt a46624198eeb4c2e442c38b0ff3bd8f52caeefd76675c36f410e2fb69014a239)
android_ndk_version=28.1.13356709
android_ndk_notice_sha256=faf0dc52cf6ce9ab09a04b0c074a378dd2565ee1ed9bc1179d83793bcdba012e
android_ndk_toolchain_sha256=789714a9076571c580cf531bdcebec776a4d889c12c3c1108adafc6e4338710a
cache=${XDG_CACHE_HOME:-$HOME/.cache}/cairnfold
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
