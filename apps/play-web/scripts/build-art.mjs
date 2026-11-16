#!/usr/bin/env node
/**
 * Builds the web player's art and sounds from the iOS app's (apps/play-ios/Pounce/Resources):
 * WebP images at the sizes the web player draws them (2x), Opus and AAC sounds, and the app
 * icons. The output is committed under src/art, src/sound and public/icons; run this again
 * after the iOS art changes. Needs cwebp, ffmpeg, pngquant and ImageMagick (`magick`).
 *
 *   node apps/play-web/scripts/build-art.mjs
 */
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const web = join(here, "..");
const res = join(web, "../play-ios/Pounce/Resources");
const xc = join(res, "Assets.xcassets");
const ART = join(web, "src/art");
const SOUND = join(web, "src/sound");
const ICONS = join(web, "public/icons");

/** The largest PNG an image set has. */
function source(name) {
  const set = [join(xc, `${name}.imageset`), ...["Cards", "Cats", "FX", "Table"].map((a) => join(xc, `${a}.spriteatlas/${name}.imageset`))].find(existsSync);
  if (!set) throw new Error(`no image set ${name}`);
  const pngs = readdirSync(set).filter((f) => f.endsWith(".png"));
  const best = pngs.find((f) => f.includes("@3x")) ?? pngs.find((f) => f.includes("@2x")) ?? pngs[0];
  return join(set, best);
}

function webp(name, width, out = name, quality = 82) {
  const to = join(ART, `${out}.webp`);
  // Resize with ImageMagick (Lanczos), then encode; alpha kept exact enough for outlines.
  const tmp = join(ART, `.${out}.png`);
  execFileSync("magick", [source(name), "-filter", "Lanczos", "-resize", `${width}x>`, tmp]);
  execFileSync("cwebp", ["-quiet", "-q", String(quality), "-alpha_q", "90", "-m", "6", tmp, "-o", to]);
  rmSync(tmp);
}

rmSync(ART, { recursive: true, force: true });
mkdirSync(ART, { recursive: true });
mkdirSync(SOUND, { recursive: true });
mkdirSync(ICONS, { recursive: true });

// Cats: every pose, 320 px (the name screen draws them largest, at 160 points).
for (let cat = 0; cat < 8; cat++) {
  for (const pose of ["idle", "awake", "away", "asleep", "celebrate", "leap", "terrified"]) webp(`cat${cat}-${pose}`, 320);
}
// Cards: drawn up to 104 points wide in a hand.
for (const name of ["card-face", "card-back", "card-shadow", "card-glow"]) webp(name, 208);
for (const name of ["card-yarn", "card-cucumber"]) webp(name, 160);
for (const coat of ["tabby", "tuxedo", "calico", "gray"]) {
  webp(`coat-${coat}`, 144);
  webp(`glyph-${coat}`, 48);
}
// The table.
webp("rug", 900, "rug", 78);
webp("rug-play", 352);
for (const name of ["tower-base", "tower-shelf", "tower-top", "shelf-badge", "crown", "tray", "tray-gold", "ring", "ring-glow", "sunburst", "paw-swipe"]) webp(name, 240);
for (const name of ["tile-fish", "tile-mouse", "tile-feather", "tile-bell"]) webp(name, 96);
for (const name of ["fx-confetti", "fx-fur", "fx-sparkle", "fx-star", "fx-yarn"]) webp(name, 96);
// Rooms and posters.
webp("room-bg", 780, "room-bg", 74);
webp("home-bg", 780, "home-bg", 74);
webp("curtain-stage", 780, "curtain-stage", 74);
webp("game-cat-tower", 768, "game-cat-tower", 78);
webp("game-tiles", 768, "game-tiles", 78);
// Controls and badges.
for (const name of [
  "icon-back", "icon-gear", "icon-plus", "icon-qr", "icon-share", "icon-phone", "icon-sound-on", "icon-sound-off",
  "icon-haptics-on", "icon-haptics-off", "icon-home", "icon-invite", "icon-dice", "icon-check", "icon-play", "icon-replay",
  "icon-keypad", "icon-leave", "icon-paw-menu", "icon-sort", "icon-remove", "icon-swap", "icon-hourglass", "icon-zzz", "icon-padlock", "icon-trash", "icon-trophy",
]) webp(name, 96);
for (const name of ["badge-bot", "badge-phone", "badge-remote", "badge-laid", "badge-skip"]) webp(name, 80);
for (const name of ["chip-plus", "toy-box", "toy-box-closed", "qr-frame", "push-priming"]) webp(name, 256);
for (const name of ["state-offline", "state-closed", "state-full", "state-stalled", "state-update"]) webp(name, 320);

// Sounds: Opus (Chrome, Firefox, Edge, Safari 17+) and AAC (older Safari).
for (const file of readdirSync(join(res, "Sounds")).filter((f) => f.endsWith(".caf"))) {
  const name = file.replace(/\.caf$/, "");
  const from = join(res, "Sounds", file);
  execFileSync("ffmpeg", ["-loglevel", "error", "-y", "-i", from, "-ac", "1", "-c:a", "libopus", "-b:a", "40k", join(SOUND, `${name}.webm`)]);
  execFileSync("ffmpeg", ["-loglevel", "error", "-y", "-i", from, "-ac", "1", "-c:a", "aac", "-b:a", "64k", join(SOUND, `${name}.m4a`)]);
}

// Icons: the app icon, plus a maskable one with the art inside the safe zone on the launch violet.
const icon = join(xc, "AppIcon.appiconset/AppIcon.png");
for (const [size, name] of [[192, "icon-192"], [512, "icon-512"], [180, "apple-touch-icon"], [32, "favicon-32"]]) {
  execFileSync("magick", [icon, "-filter", "Lanczos", "-resize", `${size}x${size}`, "-strip", join(ICONS, `${name}.png`)]);
}
execFileSync("magick", [
  "-size", "512x512", "xc:#2A0F5C", "(", icon, "-resize", "410x410", ")", "-gravity", "center", "-composite", "-strip",
  join(ICONS, "icon-maskable-512.png"),
]);
// Icons are PNG (every browser's manifest reads it); quantized, they are a tenth the size.
for (const file of readdirSync(ICONS).filter((f) => f.endsWith(".png"))) {
  execFileSync("pngquant", ["--force", "--skip-if-larger", "--quality", "50-90", "--ext", ".png", join(ICONS, file)]);
}
console.log("art built");
