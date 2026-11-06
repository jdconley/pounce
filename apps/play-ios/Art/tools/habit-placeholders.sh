#!/bin/bash
# Placeholder art for the daily habit rewards (spec §9.6, manifest batch "habit"), drawn from the
# existing Loud Toy art and plain shapes so screens read right before the Codex art lands. Every
# file carries the "_ph" suffix, so placeholders.sh --report lists them and build-assets.sh
# replaces each by name with real art (PR 8). Never touches an entry that already has real art.
#
#   habit-placeholders.sh            render missing habit placeholders
#   habit-placeholders.sh --force    re-render every habit placeholder
set -euo pipefail
source "$(dirname "$0")/lib.sh"
force=0
[ "${1:-}" = "--force" ] && force=1

V="#7B2FF7"; M="#FF2BD6"; T="#12E0D0"; O="#FF8A00"; S="#2EA8FF"; L="#8BE000"; G="#FFC21A"; W="#FFFFFF"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

src() { # src <name>: the catalog's @3x PNG of an existing entry
  local d; d="$(entry_dir "$1")"
  echo "$d/$(jq -r '.images[] | select(.scale=="3x") | .filename' "$d/Contents.json")"
}

# put <name> <png at @3x>: writes <name>_ph@3x / @2x and the Contents.json.
put() {
  local name="$1" png="$2" dir; dir="$(entry_dir "$name")"
  if [ -f "$dir/Contents.json" ] && ! is_placeholder "$name"; then return; fi
  if [ -f "$dir/Contents.json" ] && [ "$force" -eq 0 ]; then return; fi
  read -r pw ph < <(point_size "$name")
  ensure_atlas_container "$name"
  mkdir -p "$dir"; clear_images "$dir"
  magick "$png" -resize "$((pw * 3))x$((ph * 3))!" -depth 8 "PNG32:$dir/${name}_ph@3x.png"
  magick "$png" -resize "$((pw * 2))x$((ph * 2))!" -depth 8 "PNG32:$dir/${name}_ph@2x.png"
  write_contents "$name" "_ph"
  echo "  $name"
}

# paw <cx> <cy> <size>: -draw ellipses for a paw (pad + four toes).
paw() {
  awk -v cx="$1" -v cy="$2" -v s="$3" 'BEGIN{
    printf "ellipse %.1f,%.1f %.1f,%.1f 0,360 ", cx, cy+s*0.12, s*0.24, s*0.19
    printf "ellipse %.1f,%.1f %.1f,%.1f 0,360 ", cx-s*0.28, cy-s*0.08, s*0.09, s*0.11
    printf "ellipse %.1f,%.1f %.1f,%.1f 0,360 ", cx-s*0.10, cy-s*0.24, s*0.09, s*0.11
    printf "ellipse %.1f,%.1f %.1f,%.1f 0,360 ", cx+s*0.10, cy-s*0.24, s*0.09, s*0.11
    printf "ellipse %.1f,%.1f %.1f,%.1f 0,360", cx+s*0.28, cy-s*0.08, s*0.09, s*0.11 }'
}

RUG="$(src rug)"; BACK="$(src card-back)"; YARN="$(src card-yarn)"; CUKE="$(src card-cucumber)"
CROWN="$(src crown)"; STAR="$(src fx-star)"; CONF="$(src fx-confetti)"; FYARN="$(src fx-yarn)"; FUR="$(src fx-fur)"
SPARK="$(src fx-sparkle)"; SUN="$(src sunburst)"; BELL="$(src icon-bell)"

echo "rugs"
rug() { # rug <name> <hue> [overlay] [overlay size]
  local out="$TMP/$1.png"
  magick "$RUG" -modulate 100,125,"$2" "$out"
  if [ -n "${3:-}" ]; then
    magick "$out" \( "$3" -resize "${4:-360}x${4:-360}" \) -gravity center -composite "$out"
  fi
  put "$1" "$out"
}
rug rug-night-sky 40 "$STAR" 300
rug rug-candy-stripe 130 "$CONF" 320
rug rug-fish-pond 60 "$FUR" 300
rug rug-royal-violet 80 "$CROWN" 360

echo "backs"
back() { # back <name> <modulate> <overlay>
  local out="$TMP/$1.png"
  magick "$BACK" -modulate "$2" \( "$3" -resize 130x130 \) -gravity center -composite "$out"
  put "$1" "$out"
}
back back-yarn-swirl 100,120,60 "$YARN"
back back-moonlit-fish 85,120,40 "$STAR"
back back-cucumber-chaos 100,130,155 "$CUKE"
back back-crown 105,130,135 "$CROWN"
back back-heart-paws 105,130,170 "$CONF"
back back-golden-yarn 120,170,145 "$YARN"

echo "condo"
condo() { # condo <stage>: a cat tree that grows a piece per stage (§9.1)
  local n="$1" out="$TMP/condo-$1.png" top=760
  [ "$n" -ge 3 ] && top=560; [ "$n" -ge 5 ] && top=380; [ "$n" -ge 7 ] && top=230; [ "$n" -ge 10 ] && top=170
  local args=(-size 900x900 xc:none)
  if [ "$n" -ge 10 ]; then args+=(\( "$SUN" -resize 900x900 \) -gravity center -composite -gravity northwest); fi
  args+=(-stroke "$INK" -strokewidth 14)
  # 1: a round cushion on the rug.
  args+=(-fill "$M" -draw "ellipse 450,790 250,60 0,360" -fill "$O" -draw "ellipse 450,770 170,38 0,360")
  # 2: a scratching post (to the top piece).
  if [ "$n" -ge 2 ]; then
    args+=(-fill "$T" -draw "rectangle 420,$top 480,770")
    for y in $(seq $((top + 40)) 60 740); do args+=(-strokewidth 6 -draw "line 420,$y 480,$((y + 22))" -strokewidth 14); done
  fi
  # 3: the first platform. 4: a hammock under it.
  [ "$n" -ge 3 ] && args+=(-fill "$V" -draw "roundrectangle 240,540 660,595 24,24")
  [ "$n" -ge 4 ] && args+=(-fill "$O" -draw "path 'M 290,595 Q 450,700 610,595 Z'")
  # 5: a second tier and a dangling yarn toy.
  if [ "$n" -ge 5 ]; then
    args+=(-fill "$L" -draw "roundrectangle 290,360 610,412 24,24" -draw "line 580,412 580,470")
    args+=(\( "$YARN" -resize 90x90 \) -geometry +535+455 -composite -stroke "$INK" -strokewidth 14)
  fi
  # 6: a tunnel.
  [ "$n" -ge 6 ] && args+=(-fill "$S" -draw "ellipse 735,745 120,85 180,360" -draw "rectangle 615,745 855,790" -fill "$INK" -draw "ellipse 735,775 55,40 180,360")
  # 7: a tower top with the crown.
  if [ "$n" -ge 7 ]; then
    args+=(-fill "$O" -draw "roundrectangle 330,$top 570,$((top + 48)) 24,24")
    args+=(\( "$CROWN" -resize 170x130 \) -geometry +365+$((top - 120)) -composite -stroke "$INK" -strokewidth 14)
  fi
  # 8: a window perch with a moon.
  [ "$n" -ge 8 ] && args+=(-fill "$T" -draw "roundrectangle 90,430 270,470 18,18" -draw "line 180,470 180,600" -fill "$G" -draw "circle 170,320 170,250" -fill "#2A0F5C" -strokewidth 0 -draw "circle 205,300 205,245" -strokewidth 14)
  # 9: string lights.
  if [ "$n" -ge 9 ]; then
    local cols=("$M" "$G" "$T" "$O" "$S" "$L") i=0
    args+=(-fill none -strokewidth 5 -draw "path 'M 80,140 Q 450,300 820,140'" -strokewidth 6)
    for x in 120 200 280 360 440 520 600 680 760; do
      local y; y=$(awk -v x="$x" 'BEGIN{t=(x-80)/740; printf "%d", (1-t)*(1-t)*140 + 2*(1-t)*t*300 + t*t*140 + 14}')
      args+=(-fill "${cols[$((i % 6))]}" -draw "circle $x,$y $x,$((y + 16))"); i=$((i + 1))
    done
    args+=(-strokewidth 14)
  fi
  # 10: a glowing rooftop deck and fireworks.
  if [ "$n" -ge 10 ]; then
    args+=(-fill "$G" -draw "roundrectangle 300,130 600,168 18,18")
    for p in "+40+40" "+760+60" "+60+600" "+780+520"; do args+=(\( "$STAR" -resize 110x110 \) -geometry "$p" -composite); done
  fi
  magick "${args[@]}" "PNG32:$out"
  put "condo-$n" "$out"
}
for n in 1 2 3 4 5 6 7 8 9 10; do condo "$n"; done

echo "toys"
toy() { # toy <id> <rarity> <index>: a candy disc with a mark; shiny and golden rings
  local out="$TMP/$1.png" cols=("$V" "$M" "$T" "$O" "$S" "$L") marks=("$FYARN" "$STAR" "$CONF" "$FUR")
  local fill="${cols[$(($3 % 6))]}" ring="$INK" width=10
  [ "$2" = shiny ] && { ring="$W"; width=14; }
  [ "$2" = golden ] && { fill="$G"; ring="$O"; width=14; }
  local args=(-size 432x432 xc:none -fill "$fill" -stroke "$INK" -strokewidth 22 -draw "circle 216,216 216,30"
              -fill none -stroke "$ring" -strokewidth "$width" -draw "circle 216,216 216,52"
              \( "${marks[$(($3 % 4))]}" -resize 230x230 \) -gravity center -composite)
  [ "$2" != common ] && args+=(\( "$SPARK" -resize 150x150 \) -gravity northeast -composite)
  if [ "$(($3 % 4))" = 3 ]; then args+=(-gravity northwest -fill "$W" -stroke "$INK" -strokewidth 6 -draw "$(paw 216 230 230)"); fi
  magick "${args[@]}" "PNG32:$out"
  put "$1" "$out"
}
i=0
while read -r id; do
  case "$id" in
    toy-rainbow-yarn|toy-glitter-mouse|toy-silver-bell|toy-moon-fish|toy-star-wand|toy-disco-ball) r=shiny ;;
    toy-golden-*) r=golden ;;
    *) r=common ;;
  esac
  toy "$id" "$r" "$i"; i=$((i + 1))
done < <(jq -r '.[] | select(.name | startswith("toy-")) | .name' "$MANIFEST")

echo "gift box"
magick -size 480x480 xc:none -stroke "$INK" -strokewidth 16 \
  -fill "$V" -draw "roundrectangle 90,210 390,440 26,26" -fill "#9B5BFF" -draw "roundrectangle 66,150 414,222 22,22" \
  -fill "$M" -draw "rectangle 212,150 268,440" -draw "ellipse 190,120 60,38 0,360" -draw "ellipse 290,120 60,38 0,360" \
  -fill "$G" -draw "circle 240,128 240,104" "PNG32:$TMP/gift-box.png"
put gift-box "$TMP/gift-box.png"
magick -size 480x480 xc:none \( "$SUN" -resize 420x420 \) -gravity center -geometry +0-40 -composite -gravity northwest \
  -stroke "$INK" -strokewidth 16 -fill "$V" -draw "roundrectangle 90,250 390,450 26,26" -fill "$M" -draw "rectangle 212,250 268,450" \
  -fill "#9B5BFF" -draw "polygon 40,120 300,40 320,100 60,180" \
  \( "$SPARK" -resize 120x120 \) -geometry +300+150 -composite \( "$SPARK" -resize 90x90 \) -geometry +110+170 -composite \
  "PNG32:$TMP/gift-box-open.png"
put gift-box-open "$TMP/gift-box-open.png"

echo "paw badges"
pb() { magick -size 360x360 xc:none -stroke "$INK" -strokewidth 16 "$@"; }
pb -fill "#9A8CC8" -draw "$(paw 180 190 330)" "PNG32:$TMP/grey.png"; put paw-badge-grey "$TMP/grey.png"
pb -fill "$O" -draw "$(paw 180 190 330)" "PNG32:$TMP/one.png"; put paw-badge-one "$TMP/one.png"
pb -fill "$M" -draw "$(paw 130 200 250)" -fill "$O" -draw "$(paw 235 165 250)" "PNG32:$TMP/both.png"; put paw-badge-both "$TMP/both.png"
pb -fill "$S" -draw "roundrectangle 30,120 330,320 40,40" -fill "$W" -strokewidth 10 -draw "line 30,180 330,180" -draw "line 30,250 330,250" \
  -fill "$G" -strokewidth 12 -draw "circle 270,80 270,40" "PNG32:$TMP/nap.png"; put paw-badge-nap "$TMP/nap.png"
pb -fill "#FF7CC8" -draw "polygon 40,250 250,40 320,110 110,320" -fill "$W" -draw "roundrectangle 130,130 230,230 18,18" \
  -fill "$M" -strokewidth 0 -draw "circle 160,160 160,150" -draw "circle 200,160 200,150" -draw "circle 160,200 160,190" -draw "circle 200,200 200,190" \
  "PNG32:$TMP/bandage.png"; put paw-badge-bandage "$TMP/bandage.png"
pb -fill none -draw "roundrectangle 130,40 230,120 24,24" -fill "$O" -draw "roundrectangle 30,100 330,320 36,36" \
  -fill "$G" -draw "rectangle 100,100 130,320" -draw "rectangle 230,100 260,320" "PNG32:$TMP/suitcase.png"
put paw-badge-suitcase "$TMP/suitcase.png"

echo "pounce bell and sleepy condo"
magick -size 720x720 xc:none -fill "$M" -stroke "$INK" -strokewidth 24 -draw "circle 360,360 360,40" \
  \( "$BELL" -resize 420x420 \) -gravity center -composite \( "$SPARK" -resize 160x160 \) -gravity northeast -composite \
  "PNG32:$TMP/pounce-bell.png"
put pounce-bell "$TMP/pounce-bell.png"
magick "$TMP/condo-5.png" \( "$(src cat2-asleep)" -resize 300x300 \) -gravity south -geometry -150+90 -composite \
  \( "$(src cat4-asleep)" -resize 300x300 \) -gravity south -geometry +150+90 -composite "PNG32:$TMP/sleepy.png"
put cats-asleep-condo "$TMP/sleepy.png"

echo "icons"
ic() { magick -size 252x252 xc:none -stroke "$INK" -strokewidth 16 "$@"; }
cp "$TMP/suitcase.png" "$TMP/icon-pause.png"; put icon-pause "$TMP/icon-pause.png"
ic -fill "$INK" -draw "polygon 120,150 132,150 128,240 124,240" -fill "$M" -draw "circle 126,96 126,26" -fill "$W" -strokewidth 0 -draw "circle 106,76 106,62" "PNG32:$TMP/pin.png"
put icon-pin "$TMP/pin.png"
ic -fill "$S" -draw "polygon 50,80 202,80 184,236 68,236" -fill "$T" -draw "roundrectangle 30,46 222,84 12,12" -draw "roundrectangle 96,20 156,50 10,10" \
  -fill none -strokewidth 10 -draw "line 100,110 106,210" -draw "line 152,110 146,210" "PNG32:$TMP/trash.png"
put icon-trash "$TMP/trash.png"
magick "$RUG" -resize 252x252 "$TMP/icon-rug.png"; put icon-rug "$TMP/icon-rug.png"
ic -fill "$W" -draw "circle 90,150 90,100" -draw "circle 150,120 150,56" -draw "circle 196,160 196,118" -draw "roundrectangle 50,140 230,206 30,30" \
  -fill "$M" -strokewidth 0 -draw "rectangle 132,118 160,206" -draw "rectangle 102,148 190,176" "PNG32:$TMP/cloud.png"
put icon-cloud-plus "$TMP/cloud.png"
heart() { awk -v x="$1" -v y="$2" -v s="$3" 'BEGIN{printf "path '\''M %d,%d C %d,%d %d,%d %d,%d C %d,%d %d,%d %d,%d Z'\''", x, y+s*0.9, x-s*1.2, y+s*0.1, x-s*0.5, y-s*0.8, x, y-s*0.15, x+s*0.5, y-s*0.8, x+s*1.2, y+s*0.1, x, y+s*0.9}'; }
ic -fill "$O" -draw "$(heart 160 120 80)" -fill "$M" -draw "$(heart 100 140 80)" "PNG32:$TMP/days.png"
put icon-days "$TMP/days.png"
ic -fill "$G" -draw "polygon 126,14 156,92 238,96 174,148 196,228 126,182 56,228 78,148 14,96 96,92" "PNG32:$TMP/weeks.png"
put icon-weeks "$TMP/weeks.png"
ic -fill none -stroke "$INK" -strokewidth 46 -draw "arc 40,40 212,212 -30,250" -stroke "$T" -strokewidth 26 -draw "arc 40,40 212,212 -30,250" \
  -fill "$T" -stroke "$INK" -strokewidth 12 -draw "polygon 168,60 240,60 212,130" "PNG32:$TMP/replay.png"
put icon-replay "$TMP/replay.png"

echo "pounce and notification settings (PR 5)"
ZZZ="$(src icon-zzz)"; PLUS="$(src icon-plus)"; DICE="$(src icon-dice)"
# The resting bell: tilted over on a violet disc, with the zzz.
magick -size 720x720 xc:none -fill "$V" -stroke "$INK" -strokewidth 24 -draw "circle 360,360 360,40" \
  \( "$BELL" -resize 400x400 -background none -rotate -28 \) -gravity center -geometry +0+30 -composite \
  \( "$ZZZ" -resize 230x230 \) -gravity northeast -geometry +40+40 -composite "PNG32:$TMP/bell-asleep.png"
put pounce-bell-asleep "$TMP/bell-asleep.png"
# New game: a big lime plus on a rug. You pick: the dice on a sky rug.
magick "$RUG" -resize 480x480 \( -size 300x300 xc:none -fill "$L" -stroke "$INK" -strokewidth 18 -draw "circle 150,150 150,12" \
  \( "$PLUS" -resize 210x210 \) -gravity center -composite \) -gravity center -composite "PNG32:$TMP/new-game.png"
put pounce-new-game "$TMP/new-game.png"
magick "$RUG" -resize 480x480 -modulate 100,130,40 \( "$DICE" -resize 300x300 \) -gravity center -composite "PNG32:$TMP/pick.png"
put pounce-pick "$TMP/pick.png"
# A clock face (In a bit; the reminder dials).
ic -fill "$O" -draw "circle 126,126 126,14" -fill "$W" -draw "circle 126,126 126,46" \
  -strokewidth 18 -draw "line 126,126 126,70" -draw "line 126,126 170,146" -fill "$M" -strokewidth 8 -draw "circle 126,126 126,112" \
  "PNG32:$TMP/clock.png"
put icon-clock "$TMP/clock.png"
# Quiet hours: a gold moon (start) and a gold sun (end).
ic -fill "$G" -draw "circle 126,126 126,16" -fill "#2A0F5C" -strokewidth 0 -draw "circle 172,96 172,24" "PNG32:$TMP/moon.png"
put icon-moon "$TMP/moon.png"
rays=(); for a in 0 45 90 135 180 225 270 315; do
  rays+=(-draw "$(awk -v a="$a" 'BEGIN{r=a*3.14159/180; printf "line %d,%d %d,%d", 126+cos(r)*78, 126+sin(r)*78, 126+cos(r)*118, 126+sin(r)*118}')")
done
ic -stroke "$O" -strokewidth 22 "${rays[@]}" -stroke "$INK" -strokewidth 14 -fill "$G" -draw "circle 126,126 126,58" "PNG32:$TMP/sun.png"
put icon-sun "$TMP/sun.png"
# Auto (learned timing): a sky clock with a sparkle.
ic -fill "$S" -draw "circle 126,140 126,30" -fill "$W" -strokewidth 16 -draw "line 126,140 126,86" -draw "line 126,140 166,160" \
  \( "$SPARK" -resize 120x120 \) -gravity northeast -composite "PNG32:$TMP/auto.png"
put icon-auto "$TMP/auto.png"
# Weekdays: a magenta calendar with five dots; weekends: a teal one with two big gold dots.
cal() { # cal <fill> <dots...as -draw args>
  local fill="$1"; shift
  ic -fill "$fill" -draw "roundrectangle 20,40 232,228 26,26" -fill "$W" -draw "roundrectangle 20,40 232,96 26,26" \
    -fill "$INK" -draw "roundrectangle 64,16 88,64 8,8" -draw "roundrectangle 164,16 188,64 8,8" "$@"
}
cal "$M" -fill "$W" -strokewidth 8 -draw "circle 56,156 56,138" -draw "circle 96,156 96,138" -draw "circle 136,156 136,138" \
  -draw "circle 176,156 176,138" -draw "circle 216,156 216,138" "PNG32:$TMP/weekday.png"
put icon-weekday "$TMP/weekday.png"
cal "$T" -fill "$G" -strokewidth 10 -draw "circle 86,162 86,128" -draw "circle 166,162 166,128" "PNG32:$TMP/weekend.png"
put icon-weekend "$TMP/weekend.png"
# Last chance: a moon with an orange paw in front of it.
ic -fill "$V" -draw "circle 126,126 126,14" -fill "$G" -draw "circle 110,104 110,40" -fill "$V" -strokewidth 0 -draw "circle 146,80 146,30" \
  -stroke "$INK" -strokewidth 10 -fill "$O" -draw "$(paw 150 168 120)" "PNG32:$TMP/last-chance.png"
put icon-last-chance "$TMP/last-chance.png"
echo "widgets (PR 6)"
CHECK="$(src icon-check)"; HOME_BG="$(src home-bg)"
# The Pounce button once sent: the bell on its magenta disc, with a big lime check badge.
magick "$(src pounce-bell)" -resize 720x720 \( -size 330x330 xc:none -fill "$L" -stroke "$INK" -strokewidth 22 -draw "circle 165,165 165,14" \
  \( "$CHECK" -resize 210x210 \) -gravity center -composite \) -gravity southeast -geometry +6+6 -composite \
  "PNG32:$TMP/bell-sent.png"
put pounce-bell-sent "$TMP/bell-sent.png"
# The widgets' backdrop: the home sky, cropped square, pushed louder, sprinkled with paws.
pawsprinkle=()
for p in "180 200 150" "560 140 110" "900 260 170" "300 620 120" "760 560 150" "140 960 130" "620 940 170" "960 860 110"; do
  read -r x y s <<< "$p"; pawsprinkle+=(-draw "$(paw "$x" "$y" "$s")")
done
magick "$HOME_BG" -gravity center -crop 1170x1170+0+0 +repage -resize 1080x1080! -modulate 105,140,100 \
  \( -size 1080x1080 xc:none -fill "#FFFFFF38" -stroke none "${pawsprinkle[@]}" \) -gravity northwest -composite \
  "PNG32:$TMP/widget-bg.png"
put widget-bg "$TMP/widget-bg.png"
echo "live table (PR 7)"
# The live table toggle: a violet phone whose Lock Screen holds the teal rug strip with two cats'
# faces, and the bell ringing at its corner.
ic -fill "$V" -draw "roundrectangle 58,8 194,244 28,28" -fill "$S" -strokewidth 0 -draw "roundrectangle 74,28 178,224 16,16" \
  -stroke "$INK" -strokewidth 10 -fill "$T" -draw "roundrectangle 64,124 188,184 16,16" \
  -fill "$O" -draw "circle 98,154 98,138" -fill "$M" -draw "circle 154,154 154,138" \
  \( "$BELL" -resize 120x120 \) -gravity northeast -geometry +0+0 -composite "PNG32:$TMP/live-table.png"
put icon-live-table "$TMP/live-table.png"
echo "parent consent (PR 9)"
# The kitten's locked bell: the pounce bell on its disc, a big gold padlock hung on its front.
lock() { # lock <size> <out>: a gold padlock, shackle up, keyhole in ink
  local s="$1"
  magick -size "${s}x${s}" xc:none -stroke "$INK" -strokewidth "$((s / 16))" \
    -fill none -draw "arc $((s * 26 / 100)),$((s * 6 / 100)) $((s * 74 / 100)),$((s * 62 / 100)) 180,360" \
    -draw "line $((s * 26 / 100)),$((s * 34 / 100)) $((s * 26 / 100)),$((s * 50 / 100))" \
    -draw "line $((s * 74 / 100)),$((s * 34 / 100)) $((s * 74 / 100)),$((s * 50 / 100))" \
    -fill none -stroke "$G" -strokewidth "$((s / 28))" -draw "arc $((s * 26 / 100)),$((s * 6 / 100)) $((s * 74 / 100)),$((s * 62 / 100)) 180,360" \
    -stroke "$INK" -strokewidth "$((s / 16))" -fill "$G" -draw "roundrectangle $((s * 14 / 100)),$((s * 44 / 100)) $((s * 86 / 100)),$((s * 94 / 100)) $((s / 9)),$((s / 9))" \
    -fill "$INK" -strokewidth 0 -draw "circle $((s / 2)),$((s * 63 / 100)) $((s / 2)),$((s * 56 / 100))" \
    -draw "polygon $((s * 46 / 100)),$((s * 66 / 100)) $((s * 54 / 100)),$((s * 66 / 100)) $((s * 56 / 100)),$((s * 82 / 100)) $((s * 44 / 100)),$((s * 82 / 100))" \
    "$2"
}
lock 360 "PNG32:$TMP/lock-big.png"
magick "$(src pounce-bell)" -resize 720x720 \( "$TMP/lock-big.png" -resize 380x380 \) -gravity south -geometry +0+40 -composite \
  "PNG32:$TMP/bell-locked.png"
put kitten-bell-locked "$TMP/bell-locked.png"
# The padlock badge (a person you can't pounce yet): the padlock on a magenta disc.
lock 252 "PNG32:$TMP/lock.png"
ic -fill "$M" -draw "circle 126,126 126,10" \( "$TMP/lock.png" -resize 170x170 \) -gravity center -geometry +0+4 -composite "PNG32:$TMP/padlock.png"
put icon-padlock "$TMP/padlock.png"
# Kittens (the parent's panel): an orange kitten face with big ears and a magenta heart.
ic -fill "$O" -draw "polygon 40,120 56,26 112,82" -draw "polygon 212,120 196,26 140,82" -draw "ellipse 126,140 92,82 0,360" \
  -fill "$INK" -strokewidth 0 -draw "circle 94,134 94,120" -draw "circle 158,134 158,120" -draw "polygon 118,160 134,160 126,170" \
  -fill "$M" -stroke "$INK" -strokewidth 10 -draw "$(heart 196 196 46)" "PNG32:$TMP/kittens.png"
put icon-kittens "$TMP/kittens.png"
# A teal phone with a lime speech bubble (the text to the parent).
ic -fill "$T" -draw "roundrectangle 62,14 190,238 26,26" -fill "$S" -strokewidth 0 -draw "roundrectangle 78,36 174,206 12,12" \
  -stroke "$INK" -strokewidth 10 -fill "$L" -draw "roundrectangle 96,70 220,140 24,24" -draw "polygon 120,136 150,136 112,168" "PNG32:$TMP/phone.png"
put icon-phone "$TMP/phone.png"
# Waiting: an orange hourglass with gold sand.
ic -fill "$O" -draw "roundrectangle 46,14 206,46 12,12" -draw "roundrectangle 46,206 206,238 12,12" \
  -fill "$S" -draw "polygon 66,46 186,46 132,126 186,206 66,206 120,126" -fill "$G" -strokewidth 0 \
  -draw "polygon 90,72 162,72 126,118" -draw "polygon 82,198 170,198 126,150" "PNG32:$TMP/hourglass.png"
put icon-hourglass "$TMP/hourglass.png"
# Turn them off: the bell on a violet disc with a magenta slash.
magick -size 252x252 xc:none -fill "$V" -stroke "$INK" -strokewidth 14 -draw "circle 126,126 126,10" \
  \( "$BELL" -resize 170x170 \) -gravity center -composite \
  -stroke "$INK" -strokewidth 34 -draw "line 50,50 202,202" -stroke "$M" -strokewidth 20 -draw "line 50,50 202,202" "PNG32:$TMP/bell-off.png"
put icon-bell-off "$TMP/bell-off.png"
# Another code (Twilio Verify): a fat lime loop arrow on a sky disc, its head at the gap.
ic -fill "$S" -draw "circle 126,126 126,10" -fill none -stroke "$INK" -strokewidth 46 -draw "arc 52,52 200,200 -20,250" \
  -stroke "$L" -strokewidth 28 -draw "arc 52,52 200,200 -20,250" \
  -stroke "$INK" -strokewidth 10 -fill "$L" -draw "polygon 150,30 232,62 160,118" "PNG32:$TMP/resend.png"
put icon-resend "$TMP/resend.png"
echo "trophy room (streaks on Home, the trophy room and adding people)"
# The shelf: a fat magenta plank with a violet lip and two orange brackets.
magick -size 1080x144 xc:none -stroke "$INK" -strokewidth 14 -fill "$M" -draw "roundrectangle 10,12 1070,74 24,24" \
  -fill "$V" -draw "roundrectangle 10,58 1070,104 20,20" -fill "$O" -draw "polygon 130,100 200,100 176,138 154,138" \
  -draw "polygon 880,100 950,100 926,138 904,138" -fill "#FFFFFF66" -strokewidth 0 -draw "roundrectangle 40,22 1040,34 6,6" \
  "PNG32:$TMP/shelf.png"
put trophy-shelf "$TMP/shelf.png"
# The lock on a still-to-earn silhouette: the gold padlock on an orange disc.
ic -fill "$O" -draw "circle 126,126 126,10" \( "$TMP/lock.png" -resize 170x170 \) -gravity center -geometry +0+4 -composite "PNG32:$TMP/trophy-lock.png"
put trophy-lock "$TMP/trophy-lock.png"
# The plus chip (add someone): a fat lime plus on a magenta disc, an orange paw at its foot.
magick -size 576x576 xc:none -stroke "$INK" -strokewidth 30 -fill "$M" -draw "circle 288,288 288,22" \
  -fill "$L" -draw "roundrectangle 238,110 338,466 30,30" -draw "roundrectangle 110,238 466,338 30,30" \
  -strokewidth 0 -fill "$L" -draw "roundrectangle 252,124 324,452 22,22" -draw "roundrectangle 124,252 452,324 22,22" \
  -stroke "$INK" -strokewidth 14 -fill "$O" -draw "$(paw 430 440 150)" "PNG32:$TMP/chip-plus.png"
put chip-plus "$TMP/chip-plus.png"
# The QR frame: a thick violet ring with cat ears on top and magenta corner paws; clear inside.
magick -size 900x900 xc:none -stroke "$INK" -strokewidth 22 -fill "$V" -draw "polygon 150,190 230,30 330,170" \
  -draw "polygon 750,190 670,30 570,170" -fill "$M" -strokewidth 0 -draw "polygon 196,160 236,82 290,156" \
  -draw "polygon 704,160 664,82 610,156" -stroke "$INK" -strokewidth 22 -fill none \
  -draw "roundrectangle 60,120 840,880 90,90" -stroke "$V" -strokewidth 60 -draw "roundrectangle 60,120 840,880 90,90" \
  -stroke "$INK" -strokewidth 10 -draw "roundrectangle 100,160 800,840 60,60" \
  -fill "$O" -stroke "$INK" -strokewidth 10 -draw "$(paw 92 860 120)" -draw "$(paw 808 860 120)" "PNG32:$TMP/qr-frame.png"
put qr-frame "$TMP/qr-frame.png"
# Records: your own streak (a magenta paw on an orange disc with a lime star), your best (the gold
# crown on violet), the longest pair streak (two paws, magenta and teal, on sky), total days (an
# orange calendar with a magenta paw) and perfect weeks (seven lime dots around a gold star).
STARS="$(src fx-star)"
ic -fill "$O" -draw "circle 126,126 126,10" -strokewidth 10 -fill "$M" -draw "$(paw 126 140 150)" \
  \( "$STARS" -resize 90x90 \) -gravity northeast -geometry +6+6 -composite "PNG32:$TMP/rec-own.png"
put icon-record-own "$TMP/rec-own.png"
ic -fill "$V" -draw "circle 126,126 126,10" \( "$CROWN" -resize 180x180 \) -gravity center -composite "PNG32:$TMP/rec-best.png"
put icon-record-best "$TMP/rec-best.png"
ic -fill "$S" -draw "circle 126,126 126,10" -strokewidth 10 -fill "$M" -draw "$(paw 94 136 120)" -fill "$T" -draw "$(paw 162 120 120)" \
  "PNG32:$TMP/rec-pair.png"
put icon-record-pair "$TMP/rec-pair.png"
ic -fill "$O" -draw "roundrectangle 22,40 230,230 26,26" -fill "$W" -draw "roundrectangle 22,40 230,94 26,26" \
  -fill "$INK" -draw "roundrectangle 66,16 90,62 8,8" -draw "roundrectangle 162,16 186,62 8,8" \
  -strokewidth 10 -fill "$M" -draw "$(paw 126 168 120)" "PNG32:$TMP/rec-days.png"
put icon-record-days "$TMP/rec-days.png"
dots=(); for k in 0 1 2 3 4 5 6; do
  dots+=(-draw "$(awk -v k="$k" 'BEGIN{a=(k*360/7-90)*3.14159/180; x=126+cos(a)*92; y=126+sin(a)*92; printf "circle %d,%d %d,%d", x, y, x+20, y}')")
done
ic -fill "$V" -draw "circle 126,126 126,10" -strokewidth 8 -fill "$L" "${dots[@]}" \( "$STARS" -resize 110x110 \) -gravity center -composite \
  "PNG32:$TMP/rec-weeks.png"
put icon-record-weeks "$TMP/rec-weeks.png"
echo "habit placeholders done"
