#!/usr/bin/env bash
# The one way to put an APK on the Quest adb reaches while keeping the players' saves:
#   quest-install.sh APK          installs over the app there. One adb refuses, an older version or another key, takes
#                                 an uninstall, which erases the app's external files folder holding the garden and
#                                 the avatars: they are copied to the host first and pushed back after the install.
#   quest-install.sh --backup DIR [APK]   copies the saves of APK's package (the game's without) to DIR by itself.
#   quest-install.sh --restore DIR [APK]  pushes such a copy back by itself.
#   quest-install.sh --package APK  prints the package APK installs as, read from its manifest: every step acts on
#                                 that package, so a build renamed to stand beside the game never touches the game.
# An APK whose manifest lacks the Quest's VR launcher category is refused: the Lepton APK shares the Quest build's
# package and version code, so adb would install the Frame's build over the Quest's.
# A copy that fails, an adb call that fails included, stops the run before anything is uninstalled: a failed read of the
# device is never taken for a device without saves. A push that fails to land every file byte for byte fails the run,
# naming the copy to restore by hand. The copies stay under $CAIRNFOLD_QUEST_SAVES
# (default ~/.local/state/cairnfold/quest-saves), files identical across copies hardlinked as one. A save is only what
# the game writes, the entries of $game_paths; what the shell pushes beside them (bench output, launch arguments, check
# drivers) is left out of both the copy and the push.
set -euo pipefail
pkg=io.github.bddapbot.cairnfold
game_paths="garden.save garden.save.bad avatars record-sessions sessions"

# package APK [quest]: the manifest's package attribute, from the APK's binary XML; with quest, failing unless the
# manifest names the Quest's VR category.
package() {
  python3 - "$@" <<'PY'
import struct, sys, zipfile
x = zipfile.ZipFile(sys.argv[1]).read("AndroidManifest.xml")
strings, at = [], 8
while at < len(x):
    kind, head, size = struct.unpack_from("<HHI", x, at)
    if kind == 0x0001:
        count, _, flags, start = struct.unpack_from("<IIII", x, at + 8)
        utf8 = flags & 0x100
        for i in range(count):
            p = at + start + struct.unpack_from("<I", x, at + head + 4 * i)[0]
            if utf8:
                p += 2 if x[p] & 0x80 else 1
                n = x[p] & 0x7F
                if x[p] & 0x80:
                    n = (n << 8) | x[p + 1]
                    p += 1
                strings.append(x[p + 1:p + 1 + n].decode())
            else:
                n = struct.unpack_from("<H", x, p)[0]
                strings.append(x[p + 2:p + 2 + 2 * n].decode("utf-16le"))
        if sys.argv[2:] == ["quest"] and "com.oculus.intent.category.VR" not in strings:
            sys.exit(f"quest-install: {sys.argv[1]} is no Quest APK: its manifest lacks com.oculus.intent.category.VR")
    elif kind == 0x0102 and strings[struct.unpack_from("<I", x, at + 20)[0]] == "manifest":
        first, step, count = struct.unpack_from("<HHH", x, at + 24)
        for i in range(count):
            a = at + 16 + first + i * step
            if strings[struct.unpack_from("<I", x, a + 4)[0]] == "package":
                print(strings[struct.unpack_from("<I", x, a + 8)[0]])
                sys.exit(0)
    at += size
sys.exit("no package in the manifest")
PY
}

if [ "$1" = --package ]; then
  package "$2"
  exit 0
fi
case $1 in
  --backup | --restore) apk=${3:-} ;;
  *) apk=$1 ;;
esac
[ -z "$apk" ] || pkg=$(package "$apk" quest)
files=/sdcard/Android/data/$pkg/files

backup() {
  local dir=$1
  mkdir -p "$dir"
  local held
  held=$(adb shell "[ -d $files ] && echo saves || echo none" < /dev/null | tr -d '\r') || held=
  case $held in
    none) echo "quest-install: no saves on the device to keep" >&2; return 0 ;;
    saves) ;;
    *) echo "quest-install: adb could not tell whether the device holds saves; stopping" >&2; exit 1 ;;
  esac
  adb pull "$files/." "$dir/" > /dev/null ||
    { echo "quest-install: the saves could not be copied off, a partial copy left in $dir; stopping" >&2; exit 1; }
  for entry in "$dir"/* "$dir"/.[!.]*; do
    [[ ! -e $entry || " $game_paths " == *" ${entry##*/} "* ]] || rm -rf "$entry"
  done
  echo "quest-install: saves copied to $dir" >&2
}

# push_verified DIR REL: DIR/REL to the same place under files, failing unless the device then holds it byte for byte.
push_verified() {
  adb push "$1/$2" "$files/$2" > /dev/null < /dev/null &&
    [ "$(adb shell sha256sum "'$files/$2'" < /dev/null | cut -d' ' -f1)" = "$(sha256sum "$1/$2" | cut -d' ' -f1)" ]
}

# The game must make every folder the saves go in, its files folder and avatars/: on a Quest 3 it cannot write into one
# the shell made, and the shell may not make one inside the game's. sessions/ appears only once record-sessions has gone
# back, so the game starts again while a pushed file brings it a folder still missing; without record-sessions the game
# never makes it, and the sessions stay in the copy. Each start is waited on until every folder is there or, with one
# there to push into, five seconds pass without another.
# A freshly installed app's files folder refuses the shell's pushes for a while after the game has made it
# (secure_mkdirs: Operation not permitted), so a restore retries refused pushes for thirty seconds in all.
restore() {
  local dir=$1 rel ok=1 pending=() left=() folders there n last still entry retries=30
  for entry in $game_paths; do
    [ -e "$dir/$entry" ] || continue
    if [ "$entry" = sessions ] && [ ! -e "$dir/record-sessions" ]; then
      echo "quest-install: recorded sessions without record-sessions stay in $dir/sessions" >&2
      continue
    fi
    while IFS= read -r rel; do pending+=("$rel"); done < <(cd "$dir" && find "$entry" -type f)
  done
  [ ${#pending[@]} -gt 0 ] || return 0
  unrestored="quest-install: the saves did not go back on the device; restore them with: $(printf '%q ' "$0" --restore "$dir" ${apk:+"$(realpath "$apk")"})"
  trap 'echo "$unrestored" >&2' EXIT
  made() {
    adb shell "for d in $(tr '\n' ' ' <<< "$folders"); do [ -d \$d ] && echo y || echo n; done" < /dev/null |
      paste -d' ' - <(cat <<< "$folders") | sed -n 's/^y //p'
  }
  while [ ${#pending[@]} -gt 0 ]; do
    folders=$(printf "$files/%s\n" "${pending[@]}" | sed 's|/[^/]*$||' | sort -u)
    if [ "$(made | wc -l)" -lt "$(wc -l <<< "$folders")" ]; then
      adb shell am start -n "$pkg/com.godot.game.GodotAppLauncher" > /dev/null
      last=0 still=0
      for _ in $(seq 60); do
        n=$(made | wc -l)
        [ "$n" -lt "$(wc -l <<< "$folders")" ] || break
        if [ "$n" -gt 0 ] && [ "$n" -eq "$last" ]; then
          still=$((still + 1))
          [ $still -lt 5 ] || break
        else
          still=0
        fi
        last=$n
        sleep 1
      done
    fi
    adb shell am force-stop "$pkg"
    there=$(made)
    left=()
    for rel in "${pending[@]}"; do
      if ! grep -qxF "$(dirname "$files/$rel")" <<< "$there"; then
        left+=("$rel")
      else
        until push_verified "$dir" "$rel"; do
          retries=$((retries - 1))
          [ $retries -gt 0 ] || { ok=; break; }
          sleep 1
        done
      fi
    done
    [ ${#left[@]} -lt ${#pending[@]} ] || break
    pending=("${left[@]}")
  done
  [ -n "$ok" ] && [ ${#left[@]} -eq 0 ] || exit 1
  trap - EXIT
  echo "quest-install: saves restored from $dir" >&2
}

case $1 in
  --backup) backup "$2"; exit 0 ;;
  --restore) restore "$2"; exit 0 ;;
esac
if failed=$(adb install -r -g "$1" 2>&1); then
  exit 0
fi
case $failed in
  *INSTALL_FAILED_VERSION_DOWNGRADE* | *INSTALL_FAILED_UPDATE_INCOMPATIBLE*)
    saves=${CAIRNFOLD_QUEST_SAVES:-$HOME/.local/state/cairnfold/quest-saves}/$(date -u +%Y%m%dT%H%M%SZ)
    backup "$saves"
    hardlink -q -t "${saves%/*}" > /dev/null || echo "quest-install: copies of the saves left unlinked" >&2
    adb uninstall "$pkg" > /dev/null
    adb install -g "$1" > /dev/null
    restore "$saves" ;;
  *) echo "$failed" >&2; exit 1 ;;
esac
