# shellcheck shell=bash disable=SC2034
# Sourced by the build scripts: every pinned download, and the fetch that verifies it.
godot_version=4.5.1
godot_release=https://github.com/godotengine/godot/releases/download/$godot_version-stable
godot_arm64=("$godot_release/Godot_v$godot_version-stable_linux.arm64.zip" 4a2c6bd5066aca9d207c75f540645e29272b129f2cf321d8ba30d922af11b00f)
godot_templates=("$godot_release/Godot_v$godot_version-stable_export_templates.tpz" 1998af37f1387684e2c211cdb483daf492fc64dc6b12096bddcdca25b6910c86)
openxr_vendors=(https://github.com/GodotVR/godot_openxr_vendors/releases/download/4.3.1-stable/godotopenxrvendorsaddon.zip 1620e9a589d205023e008ea27430843f5b8bb2690b62d08bd1fadc87c49b2e3e)
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
