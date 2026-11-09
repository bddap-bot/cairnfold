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

# stranded DIR: from here on, a run that dies names the command that puts DIR back.
stranded() {
  unrestored="quest-install: the saves did not go back on the device; restore them with: $(printf '%q ' "$0" --restore "$1" ${apk:+"$(realpath "$apk")"})"
  trap 'echo "$unrestored" >&2' EXIT
}

# A restore never starts the game, so an unworn headset's Guardian or standby cannot hold it: each save goes back by
# one push, which makes the folders it needs, and what the push made is opened to the game. On a Quest 3 a folder or
# file the shell makes stays the shell's, which the game may not write; the game's start makes files/ and
# Android/data/<package> its own. The device's hashes of the copy's files must then match the copy's.
# A freshly installed app's files folder refuses the shell's writes for a while (secure_mkdirs: Operation not
# permitted), so a restore retries refused ones for thirty seconds in all.
restore() {
  local dir=$1 entry entries=() listed tries=30
  [ -d "$dir" ] || { echo "quest-install: no copy of saves at $dir" >&2; exit 1; }
  for entry in $game_paths; do
    [ -z "$(find "$dir/$entry" -type f -print -quit 2> /dev/null)" ] || entries+=("$entry")
  done
  [ ${#entries[@]} -gt 0 ] || { trap - EXIT; return 0; }
  stranded "$dir"
  retried() {
    until "$@"; do
      tries=$((tries - 1))
      [ $tries -gt 0 ] || return 1
      sleep 1
    done
  }
  retried adb shell "mkdir -p $files" < /dev/null || exit 1
  for entry in "${entries[@]}"; do
    retried adb push "$dir/$entry" "$files/" > /dev/null < /dev/null || exit 1
  done
  retried adb shell "cd $files && find ${entries[*]} -user \$(id -u) -exec chmod a+rwX {} +" < /dev/null || exit 1
  listed=$(cd "$dir" && find "${entries[@]}" -type f | sed "s/'/'\\\\''/g; s/.*/'&'/" | tr '\n' ' ')
  sums() { tr -d '\r' | LC_ALL=C sort; }
  [ "$(adb shell "cd $files && sha256sum $listed" < /dev/null | sums)" = \
    "$(cd "$dir" && find "${entries[@]}" -type f -exec sha256sum {} + | sums)" ] || exit 1
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
    stranded "$saves"
    adb uninstall "$pkg" > /dev/null
    adb install -g "$1" > /dev/null
    restore "$saves" ;;
  *) echo "$failed" >&2; exit 1 ;;
esac
