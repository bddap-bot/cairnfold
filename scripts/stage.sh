# shellcheck shell=bash disable=SC2154
# Sourced by package.sh and android.sh once root, template (under templates/ in Godot's export templates), steam and
# steam_dir are set.
# shellcheck source=scripts/pins.sh
. "$root/scripts/pins.sh"
case $(godot4 --version 2>/dev/null) in "$godot_version".stable*) ;; *) echo "$(basename "$0" .sh): godot4 is not $godot_version" >&2; exit 1 ;; esac
templates=$(fetch "${godot_templates[@]}")

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
export XDG_DATA_HOME=$stage/data XDG_CONFIG_HOME=$stage/config
tdir=$XDG_DATA_HOME/godot/export_templates/$godot_version.stable
mkdir -p "$tdir"
unzip -p "$templates" "templates/$template" > "$tdir/$template"
echo "$godot_version.stable" > "$tdir/version.txt"

git -C "$root" archive HEAD game | tar -x -C "$stage"
printf '[gd_resource type="Resource" format=3]\n[resource]\nmetadata/revision = "%s"\n' "$(git -C "$root" rev-parse HEAD)" > "$stage/game/revision.tres"
if [ -n "$steam" ]; then
  unzip -q "$(fetch "${godotsteam[@]}")" addons/godotsteam/godotsteam.gdextension "addons/godotsteam/$steam_dir/*" -d "$stage/game"
fi
