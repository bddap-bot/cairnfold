#!/usr/bin/env bash
# The one way to put an APK on the Quest adb reaches while keeping the players' saves:
#   quest-install.sh APK          installs over the app there. One adb refuses, an older version or another key, takes
#                                 an uninstall, which erases the app's external files folder holding the garden and
#                                 the avatars: they are copied to the host first and pushed back after the install.
#   quest-install.sh --restore DIR  pushes such a copy back by itself.
#   quest-install.sh --package APK  prints the package APK installs as, read from its manifest: every step acts on
#                                 that package, so a build renamed to stand beside the game never touches the game.
# Saves never block an install: a copy that fails is reported and the install goes on. A push that fails to land every
# file byte for byte fails the run, naming the copy to restore by hand. The copies stay under $NESTCOMBE_QUEST_SAVES
# (default ~/.local/state/nestcombe/quest-saves). Bench output, bench/ and bench.json, is not a save and is left out.
set -euo pipefail
pkg=io.github.bddapbot.nestcombe

# package APK: the manifest's package attribute, from the APK's binary XML.
package() {
  python3 - "$1" <<'PY'
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
[ "$1" = --restore ] || pkg=$(package "$1")
files=/sdcard/Android/data/$pkg/files

backup() {
  local dir=$1
  mkdir -p "$dir"
  adb shell "[ -d $files ]" || { echo "quest-install: no saves on the device to keep" >&2; return 0; }
  if adb pull "$files/." "$dir/" > /dev/null; then
    rm -rf "$dir/bench" "$dir/bench.json"
    echo "quest-install: saves copied to $dir" >&2
  else
    echo "quest-install: the saves could not be copied off; installing without them" >&2
  fi
}

# The game must make every folder the saves go in, its files folder and avatars/: on a Quest 3 it cannot write into one
# the shell made, and the shell may not make one inside the game's.
restore() {
  local dir=$1 rel ok=1 folders
  [ -n "$(ls -A "$dir" 2> /dev/null)" ] || return 0
  folders=$(cd "$dir" && find . -mindepth 1 -type d | sed "s|^\.|$files|" | tr '\n' ' ')
  if ! adb shell "for d in $files $folders; do [ -d \$d ] || exit 1; done"; then
    adb shell am start -n "$pkg/com.godot.game.GodotAppLauncher" > /dev/null
    for _ in $(seq 60); do
      adb shell "for d in $files $folders; do [ -d \$d ] || exit 1; done" && break
      sleep 1
    done
  fi
  adb shell am force-stop "$pkg"
  while IFS= read -r rel; do
    adb push "$dir/$rel" "$files/$rel" > /dev/null < /dev/null &&
      [ "$(adb shell sha256sum "'$files/$rel'" < /dev/null | cut -d' ' -f1)" = "$(sha256sum "$dir/$rel" | cut -d' ' -f1)" ] || ok=
  done < <(cd "$dir" && find . -type f | sed 's|^\./||')
  [ -n "$ok" ] || { echo "quest-install: the saves did not go back on the device; restore them with: $0 --restore $dir" >&2; exit 1; }
  echo "quest-install: saves restored from $dir" >&2
}

if [ "$1" = --restore ]; then
  restore "$2"
  exit 0
fi
if failed=$(adb install -r -g "$1" 2>&1); then
  exit 0
fi
case $failed in
  *INSTALL_FAILED_VERSION_DOWNGRADE* | *INSTALL_FAILED_UPDATE_INCOMPATIBLE*)
    saves=${NESTCOMBE_QUEST_SAVES:-$HOME/.local/state/nestcombe/quest-saves}/$(date -u +%Y%m%dT%H%M%SZ)
    backup "$saves"
    adb uninstall "$pkg" > /dev/null
    adb install -g "$1" > /dev/null
    restore "$saves" ;;
  *) echo "$failed" >&2; exit 1 ;;
esac
