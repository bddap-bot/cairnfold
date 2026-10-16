#!/usr/bin/env bash
# Records demo/trailer.json with the game's own audio and encodes it for the Steam store, ending on
# steam/logo.png: steam-trailer.sh OUT.mp4
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mp4=$(realpath -m "$1")
frames=$(mktemp -d)
trap 'rm -rf "$frames"' EXIT
"$root/scripts/check.sh"
# Movie time is fixed-step, so the render may run far slower than real time without changing a frame.
NESTCOMBE_QUIT_AFTER=200 NESTCOMBE_TIMEOUT=7200 "$root/scripts/render.sh" "$root/demo/trailer.json" "$frames" \
  --resolution 1920x1080 --write-movie "$frames/frame.png" --fixed-fps 30
seconds=$(python3 -c "import sys; print(int(sys.argv[1]) / 30)" "$(find "$frames" -name 'frame*.png' | wc -l)")
end=$(python3 -c "import sys; print(float(sys.argv[1]) - 2)" "$seconds")
# Steam asks for H.264 + AAC at 5000 kbps or more; a fixed bitrate keeps calm shots above that floor.
ffmpeg -y -loglevel error -framerate 30 -i "$frames/frame%08d.png" -i "$frames/frame.wav" -loop 1 -i "$root/steam/logo.png" \
  -filter_complex "[2]scale=960:-1,format=rgba,fade=in:st=$((${end%.*} - 3)):d=1:alpha=1[logo];
    [0]fade=in:d=1[scene]; [scene][logo]overlay=(W-w)/2:(H-h)/2-80:shortest=1,fade=out:st=$end:d=2,format=yuv420p[v];
    [1]afade=in:d=1,afade=out:st=$end:d=2[a]" \
  -map '[v]' -map '[a]' -t "$seconds" -c:v libx264 -preset slow -profile:v high -b:v 8000k -minrate 6000k -maxrate 12000k -bufsize 16000k \
  -r 30 -c:a aac -b:a 192k -ar 48000 -ac 2 -movflags +faststart "$mp4"
ffprobe -v error -show_entries format=duration,bit_rate:stream=codec_name,width,height,r_frame_rate -of compact "$mp4"
