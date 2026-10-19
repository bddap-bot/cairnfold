#!/usr/bin/env bash
# The one way to put an APK on the Quest adb reaches while keeping the players' saves:
#   quest-install.sh APK          installs over the app there. One adb refuses, an older version or another key, takes
#                                 an uninstall, which erases the app's external files folder holding the garden and
#                                 the avatars: they are copied to the host first and pushed back after the install.
#   quest-install.sh --restore DIR  pushes such a copy back by itself.
# Saves never block an install: a copy that fails is reported and the install goes on. A push that fails to land every
# file byte for byte fails the run, naming the copy to restore by hand. The copies stay under $NESTCOMBE_QUEST_SAVES
# (default ~/.local/state/nestcombe/quest-saves). Bench output, bench/ and bench.json, is not a save and is left out.
set -euo pipefail
pkg=io.github.bddapbot.nestcombe
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
