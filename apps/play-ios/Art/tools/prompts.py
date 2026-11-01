#!/usr/bin/env python3
"""Writes every Codex prompt to Art/prompts/<batch>/<name>.txt (batch = manifest "batch").

The 128 manifest assets were generated one subject per image with tools/gen.sh (style sample
attached as reference; pose sprites also got the cat's idle PNG as a second reference) on a
flat #D9D9D9 background, then cut out with cut.sh (Vision) or cutkey.sh (colour key, for
subjects Vision mis-masks: card-face, icon-qr, icon-haptics-on, icon-sound-on, icon-hold,
icon-delete, icon-remove, icon-leave, icon-swap). Procedural, no prompt: card-glow, card-shadow,
ring-glow, sunburst, fx-sparkle (procedural.sh). Full-bleed, no cutout: room-bg, home-bg,
curtain-stage, AppIcon, game-tile (center-cropped 3:2 -> 164:120 into cut/). Then build-assets.sh.
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
D = os.path.join(HERE, "..", "prompts")
import json
BATCH = {a["name"]: a["batch"] for a in json.load(open(os.path.join(HERE, "..", "manifest.json")))}

STYLE = ("Use your image generation tool to generate ONE image. Art direction (most important): match the attached "
"reference image's style exactly - look and feel of Bloons TD6 and Supercell games (Clash Royale, Brawl Stars) - LOUD, "
"fun, cartoony, juicy. Glossy 3D-rendered cartoon look with chunky rounded shapes, VERY thick dark ink outlines "
"(#1B0B3A), high-contrast highlights and rim light, extremely saturated candy colors (violet, hot magenta, electric "
"teal, sunny orange, sky blue, lime accents), lots of energy. NO beige, NO muted earth tones, NO cream, NO pastel, never "
"the red/blue/green/yellow four-color set. The game is Cat Tower, an original mobile card game with cats. No emoji, no "
"logos, no watermark, NO words, letters or numbers anywhere in the image.")

SINGLE = ("Composition (required): exactly ONE single object, centered, filling about 65% of the frame, on a perfectly "
"flat plain light-gray background (#D9D9D9) - no gradient, no vignette, no floor, no cast shadow, no other objects. "
"Generous empty margin on all four sides; nothing touches or is cropped by the edges. The thick dark outline is the "
"outermost edge of the object - no white sticker border or halo outside it. Square image.")

def full(aspect):
    return (f"Composition (required): a full-bleed {aspect} image, painted edge to edge, no border, no frame, no rounded "
            "corners, no device frame, no UI, no text.")

def w(name, subject, comp=SINGLE):
    os.makedirs(os.path.join(D, BATCH[name]), exist_ok=True)
    with open(os.path.join(D, BATCH[name], name + ".txt"), "w") as f:
        f.write(f"{STYLE}\n\nSUBJECT: {subject}\n\n{comp}\n")

CATS = [
 "an orange tabby cat: bright sunny-orange fur with bold darker-orange tiger stripes, white muzzle and white chest, pink nose, big shiny green eyes",
 "a tuxedo cat: glossy jet-black fur with a crisp white chest bib, white muzzle and four white paws, big shiny amber-gold eyes, pink nose",
 "a calico cat: bright white fur with big bold patches of vivid orange and jet black (a black patch over one ear, an orange patch over the other), big shiny sky-blue eyes, pink nose",
 "a gray cat: cool blue-slate gray fur (definitely not brown or beige), slightly lighter gray chest, big shiny lime-green eyes, pink nose",
 "a solid black cat: glossy jet-black fur with a strong violet rim-light sheen, huge shiny glowing yellow-lime eyes, small pink nose",
 "a white fluffy longhair cat: pure bright-white fluffy fur with cool sky-blue and lilac shading in the shadows (never cream), extra fluffy cheeks and chest ruff, bright pink ears and nose, big shiny electric-teal eyes",
 "a siamese cat: icy white body with cool lilac shading (never cream or beige), dark chocolate-violet points on the face mask, ears, paws and tail, big shiny vivid sky-blue eyes",
 "a tortoiseshell (tortie) cat: mottled jet-black fur splashed with bright orange patches and streaks all over (no white), big shiny golden-yellow eyes, pink nose",
]
POSES = {
 "idle":      "full body, sitting upright, front-facing, calm and a little smug, tail curled around its front paws",
 "awake":     "full body, sitting bolt upright, alert: ears straight up, eyes huge and wide open, head perked, tail up",
 "away":      "full body, curled up lying down in a round loaf, eyes half-closed and bored, ignoring everyone, tail wrapped around",
 "asleep":    "full body, curled up into a tight sleeping ball, eyes fully closed, peaceful smile, tail wrapped over its nose",
 "leap":      "full body, mid-jump leaping upward and to the right, body fully stretched out long, front paws reaching forward, back legs extended, tail streaming behind, joyful face",
 "terrified": "full body, terrified: back arched high like a Halloween cat, all fur standing on end and puffed out, tail bottle-brushed straight up, eyes huge and wide, mouth open in a shriek",
 "celebrate": "full body, standing up on its hind legs celebrating, both front paws thrown up in the air, mouth wide open in a huge happy grin, eyes squeezed happy",
}
for i, c in enumerate(CATS):
    for p, d in POSES.items():
        consist = "" if p == "idle" else (" This is EXACTLY the same character as the cat in the second attached reference image: identical "
            "coat colors, markings, eye color, face shape and proportions - only the pose changes.")
        w(f"cat{i}-{p}", f"a single cartoon cat character, {c}. Pose: {d}. Big head, chunky toy proportions, very thick dark outline around the whole silhouette.{consist}")

# --- cards ---
w("card-face", "a single blank playing card standing upright in portrait orientation (about 64:90), front view, perfectly flat and straight-on (not tilted, no perspective): a bright pure-white face inside a thick glossy violet rounded-rectangle rim with highlights, very thick dark ink outline. The white face is COMPLETELY EMPTY - no numeral, no art, no glyph, no pattern.")
w("card-back", "a single playing card back standing upright in portrait orientation (about 64:90), front view, perfectly flat and straight-on (not tilted): glossy deep violet card with a thick lighter-violet rounded rim, a big chunky glossy paw print centered on it in bright lilac-white with a hot-magenta glow, subtle diagonal sparkle pattern, very thick dark ink outline.")
COATS = {
 "tabby":  "an orange tabby cat (sunny-orange fur, bold darker-orange stripes, white muzzle, green eyes)",
 "tuxedo": "a tuxedo cat (jet-black fur, white muzzle and chest, amber eyes, wearing a small hot-magenta bow tie)",
 "calico": "a calico cat (white fur with bold orange and black patches, sky-blue eyes)",
 "gray":   "a gray cat (cool blue-slate gray fur, lime-green eyes)",
}
for k, c in COATS.items():
    w(f"coat-{k}", f"a single big-eyed excited cartoon cat HEAD only (head and a hint of neck, no body), front-facing, mouth open in a happy shout, of {c}. Exactly like the cat faces on the cards in the reference image.")
GLY = {
 "tabby":  "a coat glyph: three bold slanted parallel stripe marks in sunny orange",
 "tuxedo": "a coat glyph: a chunky bow tie in hot magenta",
 "calico": "a coat glyph: a blob made of three overlapping round patches - one orange, one jet black, one white",
 "gray":   "a coat glyph: a chunky paw print in violet",
}
for k, d in GLY.items():
    w(f"glyph-{k}", f"{d}. A very simple flat-ish icon with bold glossy fill and a VERY thick dark ink outline, readable at 16 pixels. Nothing else.")
w("card-yarn", "a glowing hot-magenta ball of yarn with visible wound strands, bursting with bright sparkles and a magenta glow, a loose strand curling off. Like the yarn wild card art in the reference image (art only, no card).")
w("card-cucumber", "a goofy screaming green cucumber character with huge googly eyes and a wide-open screaming mouth with tongue, little motion lines around it, slightly tilted. Like the cucumber on the skip card in the reference image (art only, no card).")

# --- table ---
w("rug", "a round living-room rug seen straight from above (top-down, perfectly circular, no perspective), thick fluffy texture, concentric stripes of hot magenta, electric teal and sunny orange, with a big lilac-white paw print in the middle on hot magenta. Exactly like the rug in the reference image.")
w("tower-base", "the BASE piece of a cat tower, seen from the front with a slight top-down 3/4 angle: a chunky wide square plinth covered in bright turquoise carpet, with the bottom of a thick golden sisal-rope post rising from its center (post cut off flat at the top). Wider than tall.")
w("tower-shelf", "ONE stackable SHELF piece of a cat tower, seen from the front with a slight top-down 3/4 angle: a chunky round-cornered platform covered in bright turquoise carpet, with a short thick golden sisal-rope post segment underneath it (cut off flat at the bottom). Wider than tall. Like the shelf in the reference image but without cushion or badge.")
w("tower-top", "the TOP piece of a cat tower, seen from the front with a slight top-down 3/4 angle: a chunky turquoise carpet platform holding a plump glossy sunny-orange round cushion bed, with a short golden sisal-rope post segment underneath (cut off flat at the bottom). Like the top of the cat tower in the reference image but without the badge.")
w("shelf-badge", "a glossy gold badge shaped like a cat head (round with two pointy ears), shiny metallic gold with highlights and a thick dark outline. The face of the badge is completely BLANK and smooth - no numeral, no features.")
w("ring", "an empty round avatar frame ring seen straight-on: a chunky glossy violet torus ring with highlights and rim light, very thick dark ink outline on both its outer and inner edges, the hole in the middle shows the plain gray background (empty).")
w("tray", "a long rounded card tray seen from slightly above: a chunky glossy violet rounded-rectangle tray with raised edges and an empty recessed middle, very thick dark outline. Much wider than tall (about 2:1).")
w("tray-gold", "a long rounded card tray seen from slightly above: a chunky glossy shiny metallic gold rounded-rectangle tray with raised edges, sparkle highlights and an empty recessed middle, very thick dark outline. Much wider than tall (about 2:1).")
w("paw-swipe", "a big cartoon claw swipe mark: three thick curved diagonal slash streaks in hot magenta with white-hot centers and a glow, like a cat paw just swiped across, thick dark outline.")
w("crown", "a chunky glossy gold cartoon crown with three rounded points, hot-magenta and electric-teal gems, shiny highlights, thick dark outline. Wider than tall.")
w("fx-star", "a single chunky glossy five-pointed star in sunny yellow-gold with rounded points, shiny highlight, very thick dark outline. Simple, readable at 24 pixels.")
w("fx-fur", "a single small cartoon puff of fluffy fur - a soft rounded cloud-like tuft in sunny orange with a lighter tip, thick dark outline. Simple, readable at 24 pixels.")
w("fx-yarn", "a single small loose bit of hot-magenta yarn: a short curly strand looping into one loop, glossy, thick dark outline. Simple, readable at 24 pixels.")
w("fx-confetti", "a single piece of confetti: a short twisted curled ribbon strip in electric teal, glossy, thick dark outline. Simple, readable at 24 pixels.")

# --- ui ---
w("room-bg", "a cozy living room at night seen from directly above (top-down view onto the floor), for the background of a portrait card-game table. Glossy deep-violet wooden floorboards; around the EDGES only: corners of a hot-magenta sofa and teal armchair, big potted plants, a glowing floor lamp, a few scattered yarn balls and cushions. The whole CENTER of the image is a big open empty area of floor (a rug and cards are drawn there later), no rug, no cats, no cards.", full("tall portrait (2:3) background"))
w("home-bg", "a cozy cartoon living room at night, front view: violet walls, a big window with a full moon and city lights, a hot-magenta sofa with cushions, potted plants, glowing warm lamps, a rug, yarn balls. Rich saturated violets, magentas and teals with warm orange lamp glows. The middle of the image is calm and uncluttered (UI buttons go on top). No cats, no people.", full("tall portrait (2:3) background"))
w("curtain-stage", "a theatre-like stage: heavy glossy deep-violet velvet curtains on both sides and a swag across the top, a bright spotlight cone shining down onto the center of an empty stage floor with a glowing hot-magenta spotlight circle. Dark violet night atmosphere with sparkles. The center is EMPTY (a cat is drawn there later). No cats, no people.", full("tall portrait (2:3) background"))
w("game-tile", "game cover art for Cat Tower: an excited orange tabby cat (orange fur, darker stripes, white muzzle, green eyes) waving from the top of a colorful turquoise-carpet cat tower with sisal posts and an orange cushion, a glowing magenta yarn ball and a couple of playing cards (white faces, violet rims, blank) flying around, on a glossy violet background with orange sunburst rays.", full("wide landscape (3:2)"))
STATES = {
 "state-closed":  "a spot illustration: a small round magenta/teal/orange striped rug with a cartoon gray cat fast asleep curled up on it, a couple of little sleep bubbles (no letters). The room is closed for the night.",
 "state-stalled": "a spot illustration: a cartoon gray cat (blue-slate gray fur) hopelessly tangled up in hot-magenta yarn, looking confused and stuck, a few loose yarn loops around it.",
 "state-offline": "a spot illustration: a cartoon tuxedo cat looking sadly at a hot-magenta yarn ball whose yarn strand ends in an unplugged electric plug lying on the ground next to it.",
 "state-full":    "a spot illustration: a small round magenta/teal/orange striped rug completely packed with six cartoon cats squeezed together shoulder to shoulder, no room left - the cats have NATURAL cat coats only: an orange tabby, a black-and-white tuxedo, a calico, a blue-slate gray cat, a solid black cat and a white fluffy cat (no purple, blue, pink or teal cats). One cat at the edge is half falling off, looking sheepish.",
 "state-update":  "a spot illustration: a cheerful cartoon orange tabby cat holding up a giant shiny crochet hook like a wrench, with a hot-magenta yarn ball and a few sparkles - it's fixing things up.",
 "push-priming":  "a spot illustration: a cartoon calico cat happily ringing a big glossy gold bell with its paw, little ring motion lines and sparkles around the bell.",
}
for k, s in STATES.items():
    w(k, s + " Grouped as one compact vignette.")
ICON = ("an app UI icon: {g}. One single chunky glossy glyph in bright sunny yellow-gold with a shiny highlight, very thick dark "
        "ink outline, bold simple silhouette readable at 28 pixels, no background shape behind it.")
ICONS = {
 "icon-plus": "a fat plus sign", "icon-keypad": "a keypad of nine rounded square keys in a 3x3 grid",
 "icon-share": "a share symbol: an arrow pointing up out of an open box", "icon-qr": "a QR-code symbol: three rounded square corner markers and a few small blocks (no readable code)",
 "icon-play": "a fat rounded play triangle pointing right", "icon-back": "a fat rounded back chevron pointing left",
 "icon-gear": "a chunky gear with rounded teeth", "icon-paw-menu": "a chunky paw print",
 "icon-sort": "a sort symbol: three horizontal rounded bars stacked, each shorter than the one above",
 "icon-bell": "a chunky bell", "icon-check": "a fat check mark", "icon-dice": "a single cartoon die showing dots (pips), seen at an angle",
 "icon-home": "a chunky house", "icon-move": "a move symbol: four fat arrows pointing up, down, left and right from a center",
 "icon-sound-on": "a speaker with sound waves", "icon-sound-off": "a speaker with a hot-magenta diagonal slash through it",
 "icon-haptics-on": "a phone with buzz vibration lines on both sides", "icon-haptics-off": "a phone with a hot-magenta diagonal slash through it",
 "icon-trophy": "a chunky trophy cup", "icon-zzz": "three small puffy sleep clouds rising diagonally (no letters)",
 "icon-delete": "a backspace key symbol: a chunky left-pointing arrow-tag shape with a fat X cut into it",
 "icon-remove": "a fat X cross mark",
 "icon-leave": "a leave symbol: an open door with a fat arrow pointing out of it to the right",
 "icon-swap": "a swap symbol: two fat curved arrows chasing each other in a circle",
 "icon-hold": "a press-and-hold symbol: a chunky round push button seen straight from the front with a paw print on its face, surrounded by two concentric thin pulse rings",
}
for k, g in ICONS.items():
    w(k, ICON.format(g=g))
BADGE = ("a tiny round status badge: a glossy {c} circle disc with a very thick dark outline, with {g} on it in white with a dark "
         "outline. Ultra simple, readable at 20 pixels.")
BADGES = {
 "badge-phone": ("electric-teal", "a simple smartphone"), "badge-remote": ("sky-blue", "a cloud with a little link chain"),
 "badge-bot": ("violet", "a robot cat head with an antenna"), "badge-skip": ("sunny-orange", "a small green cucumber with a curved arrow over it"),
 "badge-laid": ("hot-magenta", "a flat playing card lying down"),
}
for k, (c, g) in BADGES.items():
    w(k, BADGE.format(c=c, g=g))
w("AppIcon", "iOS app icon for Cat Tower: a big-eyed excited orange tabby cat (sunny-orange fur, bold darker stripes, white muzzle, green eyes) waving one paw from the top of a chunky turquoise-carpet cat tower with golden sisal posts and an orange cushion, on a glossy deep-violet background with soft orange-magenta sunburst rays. The cat's face is large and fills the upper half. Bold, readable at small size.",
  "Composition (required): a full-bleed SQUARE image painted edge to edge, no border, NO rounded corners (square corners, iOS masks it), no text, no letters, no logo.")
print("prompts written to", os.path.abspath(D))
