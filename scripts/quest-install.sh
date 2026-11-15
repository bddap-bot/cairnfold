#!/usr/bin/env bash
# Installs an APK on the Quest adb reaches, keeping the players' saves:
#   quest-install.sh APK            an install adb refuses (a downgrade, another key) takes an uninstall, which erases
#                                   the files folder: the saves go under $CAIRNFOLD_QUEST_SAVES first and back after
#   quest-install.sh --backup|--restore DIR [APK]   copies the saves of APK's package (else the game's) to DIR, or back
#   quest-install.sh --package APK  prints the package every step acts on, so a renamed build leaves the game be
# All but --package refuse a non-Quest APK: the Lepton APK shares the Quest build's package and version code.
# A failed read of the device stops the run before any uninstall. A save is only an entry of $game_paths, never what
# the shell pushes beside them (bench output, launch arguments).
set -euo pipefail
pkg=io.github.bddapbot.cairnfold
game_paths="garden.save garden.save.bad avatars record-sessions sessions"

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

stranded() {
  unrestored="quest-install: the saves did not go back on the device; restore them with: $(printf '%q ' "$0" --restore "$1" ${apk:+"$(realpath "$apk")"})"
  trap 'echo "$unrestored" >&2' EXIT
}

# On a Quest 3 what the shell makes stays the shell's, which the game may not write, so what each push made is opened
# to the game. A fresh install's files folder refuses the shell's writes for a while (secure_mkdirs: Operation not
# permitted), hence the retries.
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
