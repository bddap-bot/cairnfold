#!/usr/bin/env bash
# Regenerates steam/ (library capsule, wide, hero, logo, icon) from desktop captures of demo/steam.json: steam-art.sh
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
out=$root/steam
shots=$(mktemp -d)
trap 'rm -rf "$shots"' EXIT
"$root/scripts/check.sh"
"$root/scripts/render.sh" "$root/demo/steam.json" "$shots" --resolution 3840x2160

# PNG time chunks would make every regeneration a diff.
save() {
  magick - -depth 8 -strip -define png:exclude-chunks=date,time "$out/$1.png"
  local size
  size=$(magick identify -format %wx%h "$out/$1.png")
  [ "$size" = "$2" ] || { echo "steam-art: $1.png is $size, want $2" >&2; exit 1; }
}

# The ">" only ever shrinks, so a crop smaller than its slot fails the size check instead of upscaling.
cut() {
  magick "$shots/$1.png" -crop "$2" +repage -resize "$3>" miff:-
}

rm -rf "$out"
mkdir -p "$out"
magick -size 1800x500 xc:none -font "$CAIRNFOLD_TITLE_FONT" -pointsize 240 -gravity center \
  -stroke '#26340f' -strokewidth 22 -fill '#26340f' -annotate +0+0 Cairnfold \
  -stroke none -tile 'gradient:#f1eee6-#b4b0a6' -annotate +0+0 Cairnfold \
  \( +clone -background '#10160a' -shadow 70x10+6+10 \) +swap -background none -layers merge +repage \
  -trim +repage -resize 800x miff:- | save logo 800x150

cut arch 1440x2160+1390+0 600x900 | magick - \( "$out/logo.png" -resize 520x \) -gravity north -geometry +0+70 -composite miff:- | save capsule 600x900
cut wide 3680x1720+80+220 920x430 | magick - \( "$out/logo.png" -resize 440x \) -gravity northwest -geometry +40+36 -composite miff:- | save wide 920x430
cut hero 3840x1240+0+300 1920x620 | save hero 1920x620
cut arch 1024x1024+1600+820 256x256 | save icon 256x256
echo "steam-art: $out"
