#!/bin/bash
# cut.sh <name>...: Vision single-name cutout raw/<name>.png -> cut/<name>.png, then erode alpha 2px
# (removes the light-gray background fringe Vision leaves outside the ink outline). Prints alpha at (0,0).
ART="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ART"
for n in "$@"; do
  swift tools/cutout.swift "raw/$n.png" cut --names "$n" >/dev/null 2>raw/logs/cut-$n.err || { echo "$n CUTFAIL $(cat raw/logs/cut-$n.err)"; continue; }
  magick "cut/$n.png" \( +clone -alpha extract -morphology Erode Disk:${ERODE:-2} \) -alpha off -compose copy_opacity -composite "PNG32:cut/$n.png"
  echo "$n $(magick identify -format '%wx%h %[pixel:p{0,0}]' cut/$n.png)"
done
