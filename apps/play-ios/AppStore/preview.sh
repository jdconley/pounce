#!/bin/bash
# The App Store app preview: records the app's own play in a simulator and cuts it to Apple's
# preview size. Footage is the Debug build's real table, fed by the scripted demo servers
# (`-demo replay`, `-demo celebrate`) and the demo streaks (`-show-us`), with no overlays.
#   AppStore/preview.sh iphone <udid>   # iPhone 17 Pro Max -> 886x1920
#   AppStore/preview.sh ipad <udid>     # iPad Pro 13-inch (M5) -> 1200x1600
# Writes AppStore/previews/<set>-preview.mp4: H.264 High 4.0, 30 fps, stereo AAC 256 kbps at
# 48 kHz, 15 to 30 seconds. `simctl recordVideo` records no sound, and the run is silent
# (`-anim-speed 1`), so the track is the game's own effects (Pounce/Resources/Sounds) laid on
# the moments they belong to. Build and install first (see capture.sh). SKIP_RECORD=1 cuts again
# from the recordings in $WORK. Needs ffmpeg with libx264.
set -euo pipefail
cd "$(dirname "$0")/.."
SET="${1:?iphone or ipad}"
DEVICE="${2:?simulator UDID}"
BUNDLE=com.conleychaos.play
CAST="${POUNCE_DEMO_CAST:-Jess,Sam,Grandma,Theo,Ruby,Grandpa}"
WORK="${WORK:-AppStore/raw/video}"
OUT=AppStore/previews
SFX=Pounce/Resources/Sounds
mkdir -p "$WORK" "$OUT"

# rec <name> <seconds> [launch args...]: the recording starts 1.5 s before the app.
rec() {
  local name="$1" secs="$2"
  shift 2
  xcrun simctl terminate "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl io "$DEVICE" recordVideo --codec h264 --force "$WORK/$SET-$name.mov" >/dev/null 2>&1 &
  local pid=$!
  sleep 1.5
  SIMCTL_CHILD_POUNCE_DEMO_CAST="$CAST" xcrun simctl launch "$DEVICE" "$BUNDLE" \
    -anim-speed 1 -uitest-reset -seed-people "$@" >/dev/null
  sleep "$secs"
  kill -INT "$pid"
  wait "$pid" 2>/dev/null || true
}

if [ -z "${SKIP_RECORD:-}" ]; then
  xcrun simctl bootstatus "$DEVICE" -b >/dev/null
  xcrun simctl status_bar "$DEVICE" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --wifiBars 3 --cellularBars 4 --dataNetwork wifi >/dev/null
  rec replay 45 -demo replay
  rec celebrate 55 -demo celebrate
  rec us 9 -demo-streaks -show-us
  xcrun simctl terminate "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true
fi

# The cut (seconds into each recording):
#   A  replay     the table on my turn, I draw, lay down two sets, play a Cucumber
#   B  celebrate  I lay down level 10 and go out, the points, the climb, the crown, game over
#   C  us         the streak with my person
# The iPad's last deal lands a little later than the phone's.
A_START=3.0; A_LEN=6.5
B_LEN=14.5
C_START=2.5; C_LEN=5.0
if [ "$SET" = ipad ]; then B_START=17.5; SCALE="scale=1200:1600:flags=lanczos"
else B_START=16.8; SCALE="scale=886:-2:flags=lanczos,crop=886:1920"; fi
FADE=0.3
B_AT=$(echo "$A_LEN - $FADE" | bc)                 # where B starts in the cut
C_AT=$(echo "$A_LEN + $B_LEN - 2 * $FADE" | bc)    # where C starts

# Sound: <file> <seconds into the cut> <volume>
CUES=(
  "sfx-flip 1.0 0.9"  "sfx-sparkle 2.7 0.8"  "sfx-whoosh 3.9 0.8"
  "sfx-sparkle 7.4 0.8"  "sfx-flip 8.5 0.9"  "sfx-pop 9.1 0.8"
  "sfx-leap 10.6 0.9"  "sfx-leap 11.8 0.9"  "sfx-fanfare 13.5 1.0"
  "sfx-pop 17.6 0.7"  "sfx-whoosh 20.3 0.7"  "sfx-sparkle 21.0 0.7"
)
inputs=(); filter=""; mix=""
i=4
for cue in "${CUES[@]}"; do
  set -- $cue
  inputs+=(-i "$SFX/$1.caf")
  ms=$(echo "$2 * 1000 / 1" | bc)
  filter+="[$i:a]aresample=48000,aformat=channel_layouts=stereo,volume=$3,adelay=$ms:all=1[s$i];"
  mix+="[s$i]"
  i=$((i + 1))
done
n=$((${#CUES[@]} + 1))
v="fps=30,$SCALE,setsar=1,format=yuv420p,setpts=PTS-STARTPTS"

ffmpeg -v error -y \
  -ss "$A_START" -t "$A_LEN" -i "$WORK/$SET-replay.mov" \
  -ss "$B_START" -t "$B_LEN" -i "$WORK/$SET-celebrate.mov" \
  -ss "$C_START" -t "$C_LEN" -i "$WORK/$SET-us.mov" \
  -f lavfi -t 30 -i anullsrc=channel_layout=stereo:sample_rate=48000 \
  "${inputs[@]}" \
  -filter_complex "[0:v]$v[a];[1:v]$v[b];[2:v]$v,tpad=stop_mode=clone:stop_duration=2[c];
    [a][b]xfade=transition=fade:duration=$FADE:offset=$B_AT[ab];
    [ab][c]xfade=transition=fade:duration=$FADE:offset=$C_AT,trim=duration=$(echo "$C_AT + $C_LEN" | bc)[vout];
    $filter[3:a]${mix}amix=inputs=$n:normalize=0:duration=first,alimiter=limit=0.9[aout]" \
  -map "[vout]" -map "[aout]" -shortest \
  -c:v libx264 -profile:v high -level:v 4.0 -pix_fmt yuv420p -r 30 -b:v 2300k -maxrate 3000k -bufsize 6000k \
  -c:a aac -b:a 256k -ar 48000 -ac 2 -movflags +faststart "$OUT/$SET-preview.mp4"
ffprobe -v error -show_entries format=duration,size:stream=codec_name,profile,level,width,height,r_frame_rate,channels,sample_rate \
  -of default=nw=1 "$OUT/$SET-preview.mp4" | tr '\n' ' '; echo
