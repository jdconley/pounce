// Builds the public site's media from the app's own art and App Store media:
//   public/static/     images, served straight from Cloudflare's static assets at /static/*
//   public/media/      the gameplay clip; the Worker serves /media/* itself, because Safari plays
//                      video only from a server that answers byte-range requests and static assets
//                      don't (src/http/media.ts)
//   src/http/site-media.ts   the paths, sizes and inlined bits the pages use
// Run after the screenshots, preview video or app icon change: node scripts/build-site-media.mjs
// Needs ffmpeg (libx264), cwebp and ImageMagick 7 (`magick`) on the PATH. The output is committed,
// so CI and the deploy need none of them. File names carry a content hash and are cached for a
// year (public/_headers); nothing here is fetched from another host.
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import qrcode from "qrcode-generator";

const api = fileURLToPath(new URL("../", import.meta.url));
const ios = join(api, "../play-ios");
const catalog = join(ios, "Pounce/Resources/Assets.xcassets");
const store = join(ios, "AppStore");
const pub = join(api, "public");
const out = join(pub, "static");
const media = join(pub, "media");
const tmp = mkdtempSync(join(tmpdir(), "pounce-site-"));

/** The one address the QR code and other sites point at; the Worker redirects it (`/get`). */
const GET_URL = "https://play.conleychaos.com/get";

const run = (cmd, args) => execFileSync(cmd, args, { stdio: ["ignore", "ignore", "inherit"] });
// No timestamps in PNGs, so a rebuild from the same sources writes the same files.
const magick = (...args) => run("magick", [...args.slice(0, -1), "-define", "png:exclude-chunks=date,time", args.at(-1)]);

/** Copies a built file into public/static (or public/media) under a content-hashed name; returns its URL path. */
function publish(file, name, ext, dir = "static") {
  const hash = createHash("sha256").update(readFileSync(file)).digest("hex").slice(0, 10);
  const path = `${name}.${hash}.${ext}`;
  copyFileSync(file, join(pub, dir, path));
  return `/${dir}/${path}`;
}

const size = (file) => {
  const [w, h] = execFileSync("magick", ["identify", "-format", "%w %h", file]).toString().split(" ").map(Number);
  return { width: w, height: h };
};

function webp(src, name, quality = 82) {
  const file = join(tmp, `${name}.webp`);
  run("cwebp", ["-quiet", "-q", String(quality), "-m", "6", "-sharp_yuv", src, "-o", file]);
  return publish(file, name, "webp");
}

function jpeg(src, name, quality = 80) {
  const file = join(tmp, `${name}.jpg`);
  magick(src, "-strip", "-interlace", "Plane", "-sampling-factor", "4:2:0", "-quality", String(quality), file);
  return publish(file, name, "jpg");
}

/** An App Store screenshot at each width, as WebP with a JPEG fallback. */
function shot(n, widths) {
  const src = join(store, `screenshots/iphone-${n}.jpg`);
  const sizes = widths.map((w) => {
    const png = join(tmp, `shot-${n}-${w}.png`);
    magick(src, "-filter", "Lanczos", "-resize", `${w}x`, png);
    return { w, ...size(png), webp: webp(png, `shot-${n}-${w}`, 78), jpg: jpeg(png, `shot-${n}-${w}`, 76) };
  });
  const first = sizes[0];
  return {
    width: first.width,
    height: first.height,
    webp: sizes.map((s) => ({ src: s.webp, w: s.w })),
    jpg: sizes.map((s) => ({ src: s.jpg, w: s.w })),
  };
}

/** A piece of the app's art (transparent PNG) at `px` wide: WebP with a PNG fallback. */
function art(asset, name, px) {
  const src = join(catalog, asset);
  const png = join(tmp, `${name}.png`);
  magick(src, "-filter", "Lanczos", "-resize", `${px}x`, "-strip", png);
  const small = join(tmp, `${name}-8.png`);
  magick(png, "-colors", "255", "-define", "png:compression-level=9", `png8:${small}`);
  const file = join(tmp, `${name}.webp`);
  run("cwebp", ["-quiet", "-q", "86", "-alpha_q", "90", "-m", "6", png, "-o", file]);
  return { ...size(png), webp: publish(file, name, "webp"), png: publish(small, name, "png") };
}

const dataUri = (file, type) => `data:${type};base64,${readFileSync(file).toString("base64")}`;

for (const dir of [out, media]) {
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
}

// --- The app icon: favicon, touch icon, and the header logo (inlined, so pages whose CSP allows
// only data: images can show it).
const icon = join(catalog, "AppIcon.appiconset/AppIcon.png");
magick(icon, "-resize", "180x180", "-strip", join(pub, "apple-touch-icon.png"));
magick(icon, "-resize", "48x48", "-strip", "-define", "icon:auto-resize=48,32,16", join(pub, "favicon.ico"));
const logoPng = join(tmp, "logo.png");
magick(icon, "-resize", "80x80", "-strip", logoPng);
const logoWebp = join(tmp, "logo.webp");
run("cwebp", ["-quiet", "-q", "80", "-m", "6", logoPng, "-o", logoWebp]);
const favPng = join(tmp, "fav.png");
magick(icon, "-resize", "32x32", "-strip", "-colors", "128", `png8:${favPng}`);
const icon192 = join(tmp, "icon-192.png");
magick(icon, "-resize", "192x192", "-strip", "-colors", "255", `png8:${icon192}`);

// --- The gameplay clip: the first 12 seconds of the App Store preview (a turn at the table),
// phone-sized, without sound. The poster is the "Your turn!" frame.
const preview = join(store, "previews/iphone-preview.mp4");
const CLIP = { width: 528, height: 1144, seconds: 12 };
const clip = join(tmp, "clip.mp4");
run("ffmpeg", [
  "-v", "error", "-y", "-ss", "0", "-t", String(CLIP.seconds), "-i", preview, "-an",
  "-vf", `scale=${CLIP.width}:${CLIP.height}:flags=lanczos,fps=30`,
  "-c:v", "libx264", "-profile:v", "high", "-level", "4.0", "-pix_fmt", "yuv420p",
  "-crf", "27", "-preset", "veryslow", "-movflags", "+faststart", clip,
]);
const posterPng = join(tmp, "poster.png");
run("ffmpeg", ["-v", "error", "-y", "-ss", "0.7", "-i", preview, "-frames:v", "1", "-vf", `scale=${CLIP.width}:${CLIP.height}:flags=lanczos`, posterPng]);

// --- The social card (Open Graph / Twitter), 1200x630: the icon, the name and two screenshots.
const og = join(tmp, "og.png");
const FONT = "/System/Library/Fonts/SFNSRounded.ttf";
const INK = "#1B0B3A";
const card = (n, file, angle) =>
  magick(
    join(store, `screenshots/iphone-${n}.jpg`), "-resize", "x540",
    "(", "+clone", "-alpha", "extract", "-draw", "fill black polygon 0,0 0,26 26,0 fill white circle 26,26 26,0",
    "(", "+clone", "-flip", ")", "-compose", "Multiply", "-composite",
    "(", "+clone", "-flop", ")", "-compose", "Multiply", "-composite", ")",
    "-alpha", "off", "-compose", "CopyOpacity", "-composite",
    "-background", "none", "-rotate", String(angle), file,
  );
card(1, join(tmp, "og-a.png"), -5);
card(3, join(tmp, "og-b.png"), 6);
const ogIcon = join(tmp, "og-icon.png");
magick(
  icon, "-resize", "168x168",
  "(", "+clone", "-alpha", "extract", "-draw", "fill black polygon 0,0 0,38 38,0 fill white circle 38,38 38,0",
  "(", "+clone", "-flip", ")", "-compose", "Multiply", "-composite",
  "(", "+clone", "-flop", ")", "-compose", "Multiply", "-composite", ")",
  "-alpha", "off", "-compose", "CopyOpacity", "-composite", ogIcon,
);
/** Chunky outlined words, like the app's: ink outline under a filled face. */
function words(label, name, pt, fill, weight) {
  const file = join(tmp, `${name}.png`);
  const outline = Math.max(4, Math.round(pt / 14));
  magick(
    "-background", "none", "-font", FONT, "-pointsize", String(pt), "-kerning", "-1",
    "-fill", fill, "-stroke", fill, "-strokewidth", String(weight), `label:${label}`,
    "-bordercolor", "none", "-border", String(outline * 3),
    "(", "+clone", "-channel", "A", "-morphology", "Dilate", `Disk:${outline}`, "+channel", "-fill", INK, "-colorize", "100",
    "(", "+clone", "-roll", `+0+${outline}`, ")", "-compose", "Over", "-composite", ")",
    "-compose", "DstOver", "-composite", file,
  );
  return file;
}
magick(
  "-size", "1200x630", "radial-gradient:#9A4DFF-#2A0F5C",
  join(tmp, "og-b.png"), "-gravity", "east", "-geometry", "+40+30", "-composite",
  join(tmp, "og-a.png"), "-gravity", "east", "-geometry", "+270-10", "-composite",
  ogIcon, "-gravity", "northwest", "-geometry", "+72+70", "-composite",
  words("Pounce", "og-1", 124, "#FFFFFF", 6), "-gravity", "northwest", "-geometry", "+58+238", "-composite",
  words("Family Games", "og-2", 64, "#FFC400", 3), "-gravity", "northwest", "-geometry", "+62+388", "-composite",
  words("Card game for couples and kids", "og-3", 30, "#FFFFFF", 1), "-gravity", "northwest", "-geometry", "+64+488", "-composite",
  og,
);

// --- The invite pages (src/http/links.ts): each of the app's eight cats as the person who
// invited (WebP only: every Safari that runs Pounce reads it), and each game's cover as the link
// preview, 1200x630, no words in it (Apple TN3156). The preview's title names the person.
const CATS = 8;
const COVERS = { "cat-tower": "game-cat-tower", tiles: "game-tiles" };
const invitePreviews = Object.fromEntries(
  Object.entries(COVERS).map(([game, asset]) => {
    const file = join(tmp, `invite-${game}.png`);
    magick(join(catalog, `${asset}.imageset/${asset}@3x.png`), "-resize", "1200x800", "-gravity", "center", "-crop", "1200x630+0+0", "+repage", file);
    return [game, jpeg(file, `invite-${game}`, 80)];
  }),
);
const inviteCats = Array.from({ length: CATS }, (_, cat) => {
  const png = join(tmp, `inviter-${cat}.png`);
  magick(join(catalog, `Cats.spriteatlas/cat${cat}-awake.imageset/cat${cat}-awake@3x.png`), "-filter", "Lanczos", "-resize", "300x", "-strip", png);
  const file = join(tmp, `inviter-${cat}.webp`);
  run("cwebp", ["-quiet", "-q", "86", "-alpha_q", "90", "-m", "6", png, "-o", file]);
  return publish(file, `inviter-${cat}`, "webp");
});

// --- The QR code for GET_URL, as one SVG path on a `size` x `size` module grid (quiet zone excluded).
const qr = qrcode(0, "M");
qr.addData(GET_URL);
qr.make();
const modules = qr.getModuleCount();
let qrPath = "";
for (let y = 0; y < modules; y++) {
  for (let x = 0; x < modules; x++) {
    if (!qr.isDark(y, x)) continue;
    let run = 1;
    while (x + run < modules && qr.isDark(y, x + run)) run++;
    qrPath += `M${x} ${y}h${run}v1h-${run}z`;
    x += run - 1;
  }
}

const badgeSrc = join(api, "assets/site/app-store-badge.svg");

const manifest = {
  logo: dataUri(logoWebp, "image/webp"),
  favicon: dataUri(favPng, "image/png"),
  icon192: publish(icon192, "icon-192", "png"),
  badge: { src: publish(badgeSrc, "app-store-badge", "svg"), width: 120, height: 40 },
  og: { src: jpeg(og, "og", 86), width: 1200, height: 630 },
  clip: { src: publish(clip, "clip", "mp4", "media"), poster: webp(posterPng, "poster", 74), posterJpg: jpeg(posterPng, "poster", 72), ...CLIP },
  shots: [1, 2, 3, 4, 5, 6].map((n) => shot(n, [320, 440, 640])),
  art: {
    leap: art("Cats.spriteatlas/cat0-leap.imageset/cat0-leap@3x.png", "cat-leap", 360),
    celebrate: art("Cats.spriteatlas/cat0-celebrate.imageset/cat0-celebrate@3x.png", "cat-celebrate", 280),
    tuxedo: art("Cats.spriteatlas/cat1-idle.imageset/cat1-idle@3x.png", "cat-tuxedo", 280),
    calico: art("Cats.spriteatlas/cat2-awake.imageset/cat2-awake@3x.png", "cat-calico", 280),
    asleep: art("Cats.spriteatlas/cat3-asleep.imageset/cat3-asleep@3x.png", "cat-asleep", 280),
    cheer: art("Cats.spriteatlas/cat4-celebrate.imageset/cat4-celebrate@3x.png", "cat-cheer", 280),
    white: art("Cats.spriteatlas/cat5-idle.imageset/cat5-idle@3x.png", "cat-white", 280),
    tile: art("game-tile.imageset/game-tile@3x.png", "game-tile", 492),
    yarn: art("toy-yarn-ball.imageset/toy-yarn-ball@3x.png", "yarn", 144),
    bell: art("push-priming.imageset/push-priming@3x.png", "cat-bell", 420),
    condo: art("condo-10.imageset/condo-10@3x.png", "condo", 480),
  },
  qr: { url: GET_URL, size: modules, path: qrPath },
  invite: { cats: inviteCats, previews: invitePreviews },
};

writeFileSync(
  join(pub, "_headers"),
  `# Written by scripts/build-site-media.mjs. Files under /static carry a content hash in their name.
/static/*
  Cache-Control: public, max-age=31536000, immutable
  X-Content-Type-Options: nosniff

/favicon.ico
  Cache-Control: public, max-age=86400

/apple-touch-icon.png
  Cache-Control: public, max-age=86400
`,
);

writeFileSync(
  join(api, "src/http/site-media.ts"),
  `/** Generated by scripts/build-site-media.mjs from the app's art and App Store media. Do not edit. */
export const MEDIA = ${JSON.stringify(manifest, null, 2)} as const;
`,
);

rmSync(tmp, { recursive: true, force: true });
console.log(`Wrote public/ and src/http/site-media.ts (QR ${modules}x${modules} for ${GET_URL})`);
