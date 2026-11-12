#!/usr/bin/env python3
"""Cuts one game's How to play video from its recording (HowTo/make.sh runs this).

    python3 -I HowTo/compose.py <game id> <raw dir> <out mp4>

Reads HowTo/beats.json (segments, beats, captions), <raw>/<game>.log (the beat times the UI test
wrote, unix seconds), <raw>/<game>.t0 (about when the recording started) and <raw>/<game>.mov, plus
the overlays cards.swift drew in <raw>/<game>-cards/.

The recording's own timestamps can't be trusted: on a busy Mac simctl stalls and its timeline
falls behind the wall clock. So the app was run with `-timecode`, which draws the wall clock in a
strip along the top edge of every frame (TouchMarks.swift). This reads that clock off each frame,
lays every segment out in real time at 30 fps (a stall shows as a held frame), crops the strip
off, then puts the title card first, crossfades the segments, and lays each beat's caption over
its stretch. H.264, no sound.
"""
import json
import os
import subprocess
import sys

game_id, raw, out = sys.argv[1], sys.argv[2], sys.argv[3]
sheet = json.load(open("HowTo/beats.json"))
game = sheet["games"][game_id]
W, H = sheet["size"]
TITLE = sheet["titleSeconds"]
FADE = 0.35
CAP_FADE = 0.15
FPS = 30
movie = f"{raw}/{game_id}.mov"

# The strip: a white start square, 24 bits, a black end square, 4 points each from x = 60 pt at
# the very top (TimeCode in TouchMarks.swift). The screen is 3x.
SCALE = 3
BITS = 24
SQUARE = 4 * SCALE
STRIP_X = 60 * SCALE
CROP_TOP = SQUARE + 2 * SCALE


def run(args, **kw):
    return subprocess.run(args, check=True, **kw)


def frame_clocks():
    """The wall clock on every frame of the recording, in order (None where there is no strip)."""
    n = BITS + 2
    data = run(["ffmpeg", "-v", "error", "-i", movie, "-fps_mode", "passthrough", "-vf",
                f"crop={n * SQUARE}:{SQUARE // 2}:{STRIP_X}:{SQUARE // 4},scale={n}:1:flags=area,format=gray",
                "-f", "rawvideo", "-"], capture_output=True).stdout
    t0 = float(open(f"{raw}/{game_id}.t0").read().strip())
    wrap = (1 << BITS) / 100
    clocks = []
    for i in range(len(data) // n):
        px = data[i * n:(i + 1) * n]
        bits = [p > 128 for p in px]
        if not bits[0] or bits[-1]:
            clocks.append(None)  # not the app (the home screen, a launch)
            continue
        value = 0
        for b in bits[1:-1]:
            value = value * 2 + (1 if b else 0)
        t = value / 100
        t += round((t0 - t) / wrap) * wrap
        clocks.append(t if abs(t - t0) < 3600 else None)
    # A misread frame shows as a clock that jumps backwards or far ahead: drop it.
    clean, last = [], None
    for t in clocks:
        if t is not None and last is not None and (t < last - 0.02 or t > last + 15):
            t = None
        clean.append(t)
        if t is not None:
            last = t
    return clean


times = {}
for line in open(f"{raw}/{game_id}.log"):
    line = line.strip()
    if line:
        e = json.loads(line)
        times[(e["seg"], e["beat"])] = e["t"]

clocks = frame_clocks()
known = [(i, c) for i, c in enumerate(clocks) if c is not None]
print(f"clock: read on {len(known)} of {len(clocks)} frames")

# Each segment's wall-clock window, and where it lands in the cut.
segments = []
at = TITLE - FADE
for s in game["segments"]:
    start = times[(s["id"], s["from"])] - s.get("lead", 0)
    end = times[(s["id"], s["to"])]
    frames = round((end - start) * FPS)
    segments.append({"id": s["id"], "start": start, "end": end, "at": at, "frames": frames})
    at += frames / FPS - FADE
total = at + FADE

# For each output frame of each segment, the last recorded frame shown by then.
plan = []  # (segment index, recorded frame index)
k0 = 0
for si, s in enumerate(segments):
    picks = []
    for k in range(s["frames"]):
        t = s["start"] + k / FPS
        while k0 + 1 < len(known) and known[k0 + 1][1] <= t:
            k0 += 1
        picks.append(known[k0][0])
    plan += [(si, p) for p in picks]
    print(f"  {s['id']}: {len(picks)} frames from {len(set(picks))} recorded ones")

# One decode pass over the recording; each segment gets its own near-lossless intermediate.
work = f"{raw}/{game_id}-cut"
os.makedirs(work, exist_ok=True)
decode = subprocess.Popen(
    ["ffmpeg", "-v", "error", "-i", movie, "-fps_mode", "passthrough", "-vf",
     f"crop=iw:ih-{CROP_TOP}:0:{CROP_TOP},scale={W}:{H}:flags=lanczos,format=rgb24", "-f", "rawvideo", "-"],
    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
size = W * H * 3
index, frame = -1, None
encoder, current = None, None
for si, want in plan:
    if si != current:
        if encoder:
            encoder.stdin.close()
            encoder.wait()
        current = si
        encoder = subprocess.Popen(
            ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS),
             "-i", "-", "-c:v", "libx264", "-preset", "veryfast", "-crf", "12", "-pix_fmt", "yuv420p",
             f"{work}/seg{si}.mp4"], stdin=subprocess.PIPE)
    while index < want:
        frame = decode.stdout.read(size)
        index += 1
    encoder.stdin.write(frame)
encoder.stdin.close()
encoder.wait()
decode.kill()  # the rest of the recording isn't needed
decode.wait()

# Each caption from its beat to the next beat in the same segment (or the segment's end).
captions = []
for s in segments:
    beats = [b for b in game["beats"] if b["seg"] == s["id"]]
    for i, b in enumerate(beats):
        # `shift` moves a caption whose beat the test can only mark late (it polls for the moment).
        a = times[(s["id"], b["beat"])] + b.get("shift", 0)
        z = times[(s["id"], beats[i + 1]["beat"])] + beats[i + 1].get("shift", 0) if i + 1 < len(beats) else s["end"]
        a, z = max(a, s["start"]), min(z, s["end"])
        captions.append((f"{raw}/{game_id}-cards/cap-{s['id']}-{b['beat']}.png",
                         s["at"] + (a - s["start"]) + 0.05, s["at"] + (z - s["start"]) - 0.1))

inputs = ["-loop", "1", "-t", f"{TITLE:.3f}", "-i", f"{raw}/{game_id}-cards/title.png"]
for i in range(len(segments)):
    inputs += ["-i", f"{work}/seg{i}.mp4"]
for path, _, _ in captions:
    inputs += ["-loop", "1", "-t", f"{total:.3f}", "-i", path]

v = f"fps={FPS},scale={W}:{H},setsar=1,format=yuv420p"
f = [f"[0:v]{v}[title]"]
for i in range(len(segments)):
    f.append(f"[{i + 1}:v]{v},setpts=PTS-STARTPTS[s{i}]")
prev = "title"
for i, s in enumerate(segments):
    f.append(f"[{prev}][s{i}]xfade=transition=fade:duration={FADE}:offset={s['at']:.3f}[x{i}]")
    prev = f"x{i}"
for j, (_, a, z) in enumerate(captions):
    n = j + 1 + len(segments)
    f.append(f"[{n}:v]format=rgba,fade=in:st={a:.3f}:d={CAP_FADE}:alpha=1,"
             f"fade=out:st={z - CAP_FADE:.3f}:d={CAP_FADE}:alpha=1[c{j}]")
    f.append(f"[{prev}][c{j}]overlay=0:0:enable='between(t,{a:.3f},{z:.3f})'[o{j}]")
    prev = f"o{j}"
f.append(f"[{prev}]format=yuv420p[vout]")

run(["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", ";\n".join(f), "-map", "[vout]", "-an",
     "-t", f"{total:.3f}", "-c:v", "libx264", "-preset", "slow", "-profile:v", "high", "-level:v", "4.0",
     "-crf", "25", "-maxrate", "1100k", "-bufsize", "2200k", "-pix_fmt", "yuv420p", "-r", str(FPS),
     "-movflags", "+faststart", out])
print(f"{out}: {total:.1f} s, {len(segments)} segments, {len(captions)} captions")
for s in segments:
    print(f"  {s['id']}: {s['end'] - s['start']:.1f} s of play, in the cut at {s['at']:.1f} s")
