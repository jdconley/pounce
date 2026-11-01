#!/bin/bash
# Procedural FX sprites, rendered at @3x of the manifest size straight into Art/cut/.
set -euo pipefail
ART="$(cd "$(dirname "$0")/.." && pwd)"; C="$ART/cut"; T="$(mktemp -d)"; mkdir -p "$C"
# card-glow 88x114pt: soft gold-white glow around a 64x90 card
magick -size 264x342 xc:none -fill "#FFE066" -draw "roundrectangle 36,36 227,305 24,24" -blur 0x18 \
  \( -size 264x342 xc:none -fill "#FFFFFF" -draw "roundrectangle 40,40 223,301 22,22" -blur 0x6 \) -compose screen -composite \
  -channel A -evaluate multiply 1.6 +channel "PNG32:$C/card-glow.png"
# card-shadow 80x106pt: soft ink shadow of a 64x90 card
magick -size 240x318 xc:none -fill "rgba(27,11,58,0.55)" -draw "roundrectangle 24,24 215,293 24,24" -blur 0x9 "PNG32:$C/card-shadow.png"
# ring-glow 96x96pt: glowing annulus around a 72pt ring (radius 108px @3x)
magick -size 288x288 xc:none -fill none -stroke "#FFD23F" -strokewidth 34 -draw "circle 144,144 144,36" -blur 0x12 \
  \( -size 288x288 xc:none -fill none -stroke "#FFF6C2" -strokewidth 10 -draw "circle 144,144 144,38" -blur 0x4 \) -compose screen -composite \
  -channel A -evaluate multiply 1.5 +channel "PNG32:$C/ring-glow.png"
# sunburst 400x400pt: 18 alternating orange/gold rays, radial fade to transparent
S=1200; R=1000; n=18; draw=""
for i in $(seq 0 $((n-1))); do
  a0=$(echo "$i*360/$n" | bc -l); a1=$(echo "($i+0.5)*360/$n" | bc -l)
  x0=$(echo "600+$R*c($a0*3.14159265/180)" | bc -l); y0=$(echo "600+$R*s($a0*3.14159265/180)" | bc -l)
  x1=$(echo "600+$R*c($a1*3.14159265/180)" | bc -l); y1=$(echo "600+$R*s($a1*3.14159265/180)" | bc -l)
  draw="$draw polygon 600,600 $x0,$y0 $x1,$y1"
done
magick -size ${S}x${S} xc:"#FF8A00" -fill "#FFC21A" -draw "$draw" \
  \( -size 500x500 radial-gradient:"#FFF6C2"-none -background none -gravity center -extent ${S}x${S} \) -compose over -composite "$T/sb.png"
magick -size ${S}x${S} xc: -fx "max(0,min(1,(1-hypot(i-600,j-600)/600)*2.6))" "$T/mask.png"
magick "$T/sb.png" "$T/mask.png" -alpha off -compose copy_opacity -composite "PNG32:$C/sunburst.png"
# fx-sparkle 24x24pt: four-point twinkle, white core + gold glow
magick -size 72x72 xc:none -fill "#FFD23F" -draw "polygon 36,2 42,30 70,36 42,42 36,70 30,42 2,36 30,30" -blur 0x2 \
  -fill "#FFFFFF" -draw "polygon 36,10 40,32 62,36 40,40 36,62 32,40 10,36 32,32" -fill white -draw "circle 36,36 36,30" "PNG32:$C/fx-sparkle.png"
rm -rf "$T"; echo procedural done
