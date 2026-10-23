#!/usr/bin/env bash
# Regenerates the store art in steam/ (store and library art, screenshots) and meta/ (Horizon Store covers, icon,
# logo, screenshots) from one set of desktop captures of demo/steam.json and demo/steam-coop.json: store-art.sh
set -euo pipefail
font=${NESTCOMBE_TITLE_FONT:-}
[ -f "$font" ] || { echo "store-art: no title font at '$font'; nix-shell sets NESTCOMBE_TITLE_FONT" >&2; exit 1; }
root=$(cd "$(dirname "$0")/.." && pwd)
title=$(sed -n 's/^config\/name="\(.*\)"$/\1/p' "$root/game/project.godot")
out=$root/steam
meta=$root/meta
shots=$(mktemp -d)
trap 'rm -rf "$shots"' EXIT
"$root/scripts/check.sh"
NESTCOMBE_QUIT_AFTER=400 "$root/scripts/render.sh" "$root/demo/steam.json" "$shots" --resolution 3840x2160

# Two players: this render hosts, a headless instance visits it and stays until the host's digest says it has its
# shot. Ports of their own, as in coop.sh.
port=$((7480 + 8 * (RANDOM % 7)))
(cd "$root/game" && exec timeout "${NESTCOMBE_TIMEOUT:-1800}" godot4 --headless --path . --xr-mode off -- --desktop \
  --script "$root/demo/steam-coop-join.json" --capture-dir "$shots" --host-port "$port" --port $((port + 8)) --avatar 1 \
  >"$shots/join.log" 2>&1) &
join=$!
NESTCOMBE_QUIT_AFTER=600 "$root/scripts/render.sh" "$root/demo/steam-coop.json" "$shots" --resolution 3840x2160 -- --port "$port" 2>&1 | tee "$shots/host.log"
kill "$join" 2>/dev/null || true
wait "$join" || true
! grep -h "driver: until" "$shots/host.log" "$shots/join.log" || { echo "store-art: the visitor never arrived" >&2; exit 1; }

# PNG time chunks would make every regeneration a diff. The wanted size is a glob, so the logo can fix only its width.
save() {
  local file=$1 size
  [[ $file == meta/* || $file == game/* ]] && file=$root/$file || file=$out/$file
  magick - -depth 8 -strip -define png:exclude-chunks=date,time -quality 92 "$file"
  size=$(magick identify -format %wx%h "$file")
  # shellcheck disable=SC2053
  [[ $size == $2 ]] || { echo "store-art: $1 is $size, want $2" >&2; exit 1; }
}

# The ">" only ever shrinks, so a crop smaller than its slot fails the size check instead of upscaling.
cut() {
  magick "$shots/$1.png" -crop "$2" +repage -resize "$3>" miff:-
}

rm -rf "$out"/*.png "$out"/*.jpg "$out/screenshots" "$meta"
mkdir -p "$out/screenshots" "$meta/screenshots"
magick -size 4000x700 xc:none -font "$font" -pointsize 320 -gravity center \
  -stroke '#26340f' -strokewidth 30 -fill '#26340f' -annotate +0+0 "$title" \
  -stroke none -tile 'gradient:#f1eee6-#b4b0a6' -annotate +0+0 "$title" \
  \( +clone -background '#10160a' -shadow 70x14+8+14 \) +swap -background none -layers merge +repage \
  -trim +repage "$shots/title.png"
magick "$shots/title.png" -resize 1280x miff:- | save logo.png '1280x*'

cut cottage 1440x2160+1200+0 600x900 | magick - \( "$out/logo.png" -resize 520x \) -gravity north -geometry +0+70 -composite miff:- | save capsule.png 600x900
cut cottage 1804x2160+1018+0 748x896 | magick - \( "$out/logo.png" -resize 640x \) -gravity north -geometry +0+80 -composite miff:- | save vertical.png 748x896
cut wide 3680x1720+80+220 920x430 | magick - \( "$out/logo.png" -resize 440x \) -gravity northwest -geometry +40+36 -composite miff:- | save wide.png 920x430
cut garden 3770x2160+35+0 1232x706 | magick - \( "$out/logo.png" -resize 600x \) -gravity northwest -geometry +54+50 -composite miff:- | save main.png 1232x706
cut wide 3840x1446+0+300 462x174 | magick - \( "$out/logo.png" -resize 440x150 \) -gravity center -composite miff:- | save small.png 462x174
cut garden 3840x2160+0+0 800x450 | magick - \( "$out/logo.png" -resize 380x \) -gravity northwest -geometry +30+26 -composite miff:- | save event.png 800x450
cut garden 3835x2160+2+0 1438x810 | magick - -modulate 75,70 miff:- | save background.png 1438x810
cut hero 3840x1240+0+300 3840x1240 | save hero.png 3840x1240
cut icon 2160x2160+870+0 256x256 | save icon.png 256x256
cut icon 2160x2160+870+0 184x184 | save icon.jpg 184x184

n=0
for shot in stroke cottage pond flowers together above dusk; do
  n=$((n + 1))
  magick "$shots/shot-$shot.png" -resize 1920x1080 miff:- | save "screenshots/$n-$shot.jpg" 1920x1080
done

# The Horizon Store's set: its covers keep the title out of their top and bottom fifths, and the hero centres it.
title() {
  magick - \( "$shots/title.png" -resize "$1x" \) -gravity "$2" -geometry "$3" -composite miff:-
}
cut garden 3840x2160+0+0 2560x1440 | title 1300 north +0+300 | save meta/cover-landscape.png 2560x1440
cut cottage 2160x2160+840+0 1440x1440 | title 1100 north +0+300 | save meta/cover-square.png 1440x1440
cut cottage 1512x2160+1164+0 1008x1440 | title 880 north +0+300 | save meta/cover-portrait.png 1008x1440
cut hero 3840x1152+0+344 3000x900 | title 1400 center +0+0 | save meta/hero.png 3000x900
cut wide 3840x1280+0+383 1080x360 | title 760 center +0+0 | save meta/mini-landscape.png 1080x360
cut icon 2160x2160+870+0 512x512 | save meta/icon.png 512x512
# The Quest's system splash shows it while the game loads; the store asks for one within four seconds of launch.
magick "$meta/cover-landscape.png" -resize 1280x720 miff:- | save game/splash.png 1280x720
magick "$shots/title.png" miff:- | save meta/logo.png '*x*'
n=0
for shot in stroke cottage pond together dusk; do
  n=$((n + 1))
  magick "$shots/shot-$shot.png" -resize 2560x1440 miff:- | save "meta/screenshots/$n-$shot.png" 2560x1440
done
echo "store-art: $out $meta"
