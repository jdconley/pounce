#!/usr/bin/env node
/**
 * Toy Tumble's shelf poster (src/art/game-tumble.webp), drawn from the iOS app's art until the
 * app's own poster lands (the iOS plan owns the art): a toy box of plush cushions in the Tuna
 * Tiles toy colours, a toy tumbling in, and a cat on the rim. Needs rsvg-convert and cwebp.
 *
 *   node apps/play-web/scripts/tumble-poster.mjs
 */
import { execFileSync } from "node:child_process";
import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const xc = join(here, "../../play-ios/Pounce/Resources/Assets.xcassets");
const out = join(here, "../src/art/game-tumble.webp");

function png(set) {
  const dir = join(xc, set);
  const files = readdirSync(dir).filter((f) => f.endsWith(".png"));
  const best = files.find((f) => f.includes("@3x")) ?? files.find((f) => f.includes("@2x")) ?? files[0];
  return `data:image/png;base64,${readFileSync(join(dir, best)).toString("base64")}`;
}

const LOOK = {
  fish: ["#4ff2e4", "#00d1c1", "#008f8a"],
  mouse: ["#9d63ff", "#7b2fff", "#4e13c4"],
  feather: ["#ffae3d", "#ff8a00", "#c85a00"],
  bell: ["#ffe66b", "#ffd21f", "#d99a00"],
};
const glyph = Object.fromEntries(Object.keys(LOOK).map((s) => [s, png(`tile-${s}.imageset`)]));
const cat = png("Cats.spriteatlas/cat1-celebrate.imageset");
const sparkle = png("FX.spriteatlas/fx-sparkle.imageset");

const C = 58;
let defs = "";
for (const [s, [top, base, side]] of Object.entries(LOOK)) {
  defs += `<linearGradient id="g-${s}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${top}"/><stop offset="0.7" stop-color="${base}"/><stop offset="1" stop-color="${side}"/></linearGradient>`;
}
function cushion(x, y, s, rot = 0) {
  const r = C * 0.3;
  return `<g transform="rotate(${rot} ${x + C / 2} ${y + C / 2})">
    <rect x="${x + 2}" y="${y + 5}" width="${C - 4}" height="${C - 4}" rx="${r}" fill="#1b0b3a"/>
    <rect x="${x + 2}" y="${y + 2}" width="${C - 4}" height="${C - 4}" rx="${r}" fill="url(#g-${s})" stroke="#1b0b3a" stroke-width="3.5"/>
    <rect x="${x + 9}" y="${y + 9}" width="${C - 18}" height="${C - 18}" rx="${r * 0.6}" fill="none" stroke="#fff" stroke-opacity="0.75" stroke-width="2" stroke-dasharray="5 4"/>
    <image href="${glyph[s]}" x="${x + C * 0.24}" y="${y + C * 0.24}" width="${C * 0.52}" height="${C * 0.52}" opacity="0.45"/>
  </g>`;
}
function fur(x, y) {
  const cx = x + C / 2;
  const cy = y + C / 2;
  const r = C * 0.36;
  return `<g><circle cx="${cx}" cy="${cy + 3}" r="${r * 1.1}" fill="#6d6e86"/>${[
    [-0.45, 0.1, 0.62],
    [0.45, 0.12, 0.6],
    [0, -0.35, 0.65],
    [0, 0.15, 0.8],
  ]
    .map(([dx, dy, k]) => `<circle cx="${cx + dx * r}" cy="${cy + dy * r}" r="${r * k}" fill="#9a9bb0"/>`)
    .join("")}<circle cx="${cx - r * 0.25}" cy="${cy - r * 0.35}" r="${r * 0.28}" fill="#c9cadb"/></g>`;
}

// The stack in the box: columns of cushions, a hairball row at the bottom, the front of the box over it.
const boxX = 210;
const boxW = 12 * C * 0.62;
const cols = 7;
const heights = [3, 4, 2, 3, 4, 3, 2];
const suits = ["fish", "bell", "mouse", "feather"];
let stack = "";
for (let c = 0; c < cols; c++) {
  for (let r = 0; r < heights[c]; r++) {
    const x = boxX + 14 + c * C;
    const y = 512 - 70 - (r + 1) * C;
    stack += r === 0 && c !== 3 ? fur(x, y) : cushion(x, y, suits[(c * 3 + r) % 4], (c + r) % 2 ? -3 : 3);
  }
}
// A T-shaped toy tumbling in.
const tx = 470;
const ty = 40;
const falling = `<g transform="rotate(-14 ${tx + C * 1.5} ${ty + C})">${cushion(tx, ty + C, "fish")}${cushion(tx + C, ty + C, "fish")}${cushion(tx + C * 2, ty + C, "fish")}${cushion(tx + C, ty, "fish")}</g>`;

const rays = Array.from({ length: 18 }, (_, i) => {
  const a = (i / 18) * Math.PI * 2;
  const b = a + Math.PI / 36;
  const R = 900;
  return `<path d="M384 300 L${384 + Math.cos(a) * R} ${300 + Math.sin(a) * R} L${384 + Math.cos(b) * R} ${300 + Math.sin(b) * R} Z" fill="#ff2e9a" opacity="0.55"/>`;
}).join("");

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="768" height="512" viewBox="0 0 768 512">
<defs>${defs}
<radialGradient id="sky" cx="0.5" cy="0.55" r="0.75"><stop offset="0" stop-color="#4fd2ff"/><stop offset="0.6" stop-color="#2e7bff"/><stop offset="1" stop-color="#5a1fd6"/></radialGradient>
<linearGradient id="wood" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffae3d"/><stop offset="1" stop-color="#e86a00"/></linearGradient>
</defs>
<rect width="768" height="512" fill="url(#sky)"/>
${rays}
${[[60, 40, 70], [330, 30, 54], [690, 210, 64], [640, 20, 44], [150, 70, 40]].map(([x, y, s]) => `<image href="${sparkle}" x="${x}" y="${y}" width="${s}" height="${s}"/>`).join("")}
${stack}
<rect x="${boxX - 20}" y="440" width="${cols * C + 68}" height="90" rx="20" fill="url(#wood)" stroke="#1b0b3a" stroke-width="6"/>
<rect x="${boxX - 30}" y="430" width="${cols * C + 88}" height="26" rx="13" fill="#ffd21f" stroke="#1b0b3a" stroke-width="6"/>
<g fill="#c85a00" opacity="0.6">${[0, 1, 2, 3].map((i) => `<circle cx="${boxX + 40 + i * 100}" cy="485" r="12"/>`).join("")}</g>
<image href="${cat}" x="-10" y="150" width="300" height="300"/>
${falling}
</svg>`;
void boxW;

const tmp = mkdtempSync(join(tmpdir(), "tumble-poster-"));
try {
  writeFileSync(join(tmp, "poster.svg"), svg);
  execFileSync("rsvg-convert", ["-w", "768", "-h", "512", join(tmp, "poster.svg"), "-o", join(tmp, "poster.png")]);
  execFileSync("cwebp", ["-quiet", "-q", "80", "-m", "6", join(tmp, "poster.png"), "-o", out]);
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
console.log(`wrote ${out}`);
