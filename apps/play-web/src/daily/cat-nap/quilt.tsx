/**
 * Cat Nap's quilt, drawn in SVG from the board alone: the cloth (a loud color and a pattern per
 * patch, thick seams between patches), "no cat" marks, the clashes and the sleeping cats. The
 * play view puts its input on top; the TV's watch view shows it alone. The same cloth as the
 * app's (`Pounce/Daily/CatNap/CatNapFabric.swift`): the pattern and the seams say which patch a
 * cell is in, so color never says it alone.
 */
import { memo } from "preact/compat";
import { useId } from "preact/hooks";

import { art, catArt, type CatPose } from "../../lib/art";

import type { Clashes, NapState, Quilt } from "@pounce/play-api/daily/cat-nap/rules";
import type { VNode } from "preact";

import "./cat-nap.css";

/** One cell is 100 units in the quilt's own coordinates. */
export const U = 100;

const INK = "#1b0b3a";
const REFUSE = "#ff3b4e";
const LIGHT = "rgba(255,255,255,0.32)";
const DARK = "rgba(27,11,58,0.2)";

type Pattern = "stripes" | "dots" | "checks" | "zigzag" | "pinstripes" | "crosshatch" | "bars" | "pluses" | "waves";
export type Cloth = { color: string; tint: string; pattern: Pattern; name: string };

export const CLOTHS: Cloth[] = [
  { color: "#7b2fff", tint: LIGHT, pattern: "stripes", name: "violet stripes" },
  { color: "#ffd21f", tint: DARK, pattern: "dots", name: "yellow dots" },
  { color: "#00d1c1", tint: DARK, pattern: "checks", name: "teal checks" },
  { color: "#ff2e9a", tint: LIGHT, pattern: "zigzag", name: "pink zigzags" },
  { color: "#9be22e", tint: DARK, pattern: "pinstripes", name: "green pinstripes" },
  { color: "#3550ff", tint: LIGHT, pattern: "crosshatch", name: "blue crosshatch" },
  { color: "#ff8a00", tint: DARK, pattern: "bars", name: "orange bars" },
  { color: "#2eb8ff", tint: DARK, pattern: "pluses", name: "sky pluses" },
  { color: "#ff7ad9", tint: DARK, pattern: "waves", name: "bubblegum waves" },
];

export const clothOf = (patch: number): Cloth => CLOTHS[patch % CLOTHS.length]!;

/** A cat for each patch, so a quilt naps with a mix of Pounce's eight cats (as the app picks). */
export const catFor = (patch: number): number => (patch * 3 + 1) % 8;

/** What the rules say about the board: clashes, whether every cat is in, and progress. */
export type Check = { clashes: Clashes; complete: boolean; placed: number };

/** The pattern tile for `pattern`, in quilt units. */
function tile(id: string, c: Cloth): VNode {
  const s = { stroke: c.tint, fill: "none", "stroke-linecap": "round" as const };
  const f = { fill: c.tint };
  const t = U / 3;
  const shape = ((): [number, number, VNode] => {
    switch (c.pattern) {
      case "stripes":
        return [t, t, <path d={`M${-t / 2} ${t / 2} L${t / 2} ${-t / 2} M0 ${t} L${t} 0 M${t / 2} ${t * 1.5} L${t * 1.5} ${t / 2}`} {...s} stroke-width={U / 9} />];
      case "dots":
        return [U / 1.25, U / 1.25, <g {...f}><circle cx={U / 5} cy={U / 5} r={U / 11} /><circle cx={U / 1.66} cy={U / 1.66} r={U / 11} /></g>];
      case "checks":
        return [2 * t, 2 * t, <g {...f}><rect width={t} height={t} /><rect x={t} y={t} width={t} height={t} /></g>];
      case "zigzag":
        return [t, t, <path d={`M0 ${t / 2} L${t / 2} ${t / 2 - U / 10} L${t} ${t / 2}`} {...s} stroke-width={U / 16} />];
      case "pinstripes":
        return [U, U / 4, <path d={`M0 ${U / 8} H${U}`} {...s} stroke-width={U / 18} />];
      case "crosshatch":
        return [U / 2.5, U / 2.5, <path d={`M0 ${U / 2.5} L${U / 2.5} 0 M0 0 L${U / 2.5} ${U / 2.5}`} {...s} stroke-width={U / 18} />];
      case "bars":
        return [t, U, <path d={`M${t / 2} 0 V${U}`} {...s} stroke-width={U / 8} />];
      case "pluses":
        return [U / 2, U / 2, <path d={`M${U / 4 - U / 10} ${U / 4} h${U / 5} M${U / 4} ${U / 4 - U / 10} v${U / 5}`} {...s} stroke-width={U / 16} />];
      case "waves":
        return [2 * t, t, <path d={`M0 ${t / 2} Q${t / 2} ${t / 2 - U / 6} ${t} ${t / 2} T${2 * t} ${t / 2}`} {...s} stroke-width={U / 16} />];
    }
  })();
  const [w, h, body] = shape;
  return (
    <pattern id={id} patternUnits="userSpaceOnUse" width={w} height={h}>
      {body}
    </pattern>
  );
}

const cellPath = (q: Quilt, keep: (cell: number) => boolean): string => {
  let d = "";
  for (let c = 0; c < q.n * q.n; c++) if (keep(c)) d += `M${(c % q.n) * U} ${Math.floor(c / q.n) * U}h${U}v${U}h${-U}z`;
  return d;
};

/** The cloth: patches, patterns, thin lines inside a patch and thick seams between patches. */
const Cloth = memo(function Cloth({ quilt, ids }: { quilt: Quilt; ids: string }) {
  const n = quilt.n;
  const side = n * U;
  let thin = "";
  let seam = "";
  for (let c = 0; c < n * n; c++) {
    const x = (c % n) * U;
    const y = Math.floor(c / n) * U;
    if (c % n < n - 1) {
      const d = `M${x + U} ${y}v${U}`;
      if (quilt.patches[c] === quilt.patches[c + 1]) thin += d;
      else seam += d;
    }
    if (Math.floor(c / n) < n - 1) {
      const d = `M${x} ${y + U}h${U}`;
      if (quilt.patches[c] === quilt.patches[c + n]) thin += d;
      else seam += d;
    }
  }
  return (
    <g aria-hidden="true">
      <defs>{Array.from({ length: n }, (_, p) => tile(`${ids}-p${p}`, clothOf(p)))}</defs>
      {Array.from({ length: n }, (_, p) => {
        const d = cellPath(quilt, (c) => quilt.patches[c] === p);
        return (
          <g key={p}>
            <path d={d} fill={clothOf(p).color} />
            <path d={d} fill={`url(#${ids}-p${p})`} />
          </g>
        );
      })}
      <path d={thin} stroke={INK} stroke-opacity={0.32} stroke-width={U / 36} />
      <path d={seam} stroke={INK} stroke-width={U / 11} stroke-linecap="round" />
      <rect
        x={U / 7}
        y={U / 7}
        width={side - (2 * U) / 7}
        height={side - (2 * U) / 7}
        rx={U / 5}
        fill="none"
        stroke="rgba(255,255,255,0.75)"
        stroke-width={U / 30}
        stroke-dasharray={`${U / 9} ${U / 11}`}
        stroke-linecap="round"
      />
    </g>
  );
});

/** The edges of a patch's cells that face another patch or the hem. */
function patchEdges(q: Quilt, patches: number[]): string {
  const n = q.n;
  let d = "";
  for (let c = 0; c < n * n; c++) {
    const p = q.patches[c]!;
    if (!patches.includes(p)) continue;
    const x = (c % n) * U;
    const y = Math.floor(c / n) * U;
    if (Math.floor(c / n) === 0 || q.patches[c - n] !== p) d += `M${x} ${y}h${U}`;
    if (Math.floor(c / n) === n - 1 || q.patches[c + n] !== p) d += `M${x} ${y + U}h${U}`;
    if (c % n === 0 || q.patches[c - 1] !== p) d += `M${x} ${y}v${U}`;
    if (c % n === n - 1 || q.patches[c + 1] !== p) d += `M${x + U} ${y}v${U}`;
  }
  return d;
}

/** The quilt as an SVG, `children` drawn on top (the play view's cells). */
export function QuiltSvg({ quilt, state, check, children, svgProps }: {
  quilt: Quilt;
  state: NapState;
  check: Check;
  children?: VNode | VNode[];
  svgProps?: Record<string, unknown>;
}) {
  const ids = `cn${useId().replace(/[^a-zA-Z0-9]/g, "")}`;
  const n = quilt.n;
  const side = n * U;
  const { clashes, complete } = check;
  const lines = cellPath(quilt, (c) => clashes.rows.includes(Math.floor(c / n)) || clashes.cols.includes(c % n));
  let xs = "";
  for (let c = 0; c < n * n; c++) {
    if (state.cells[c] !== 1) continue;
    const x = (c % n) * U + U * 0.36;
    const y = Math.floor(c / n) * U + U * 0.36;
    const s = U * 0.28;
    xs += `M${x} ${y}l${s} ${s}M${x + s} ${y}l${-s} ${s}`;
  }
  const radius = U / 3.5;
  return (
    <svg class={`cn-quilt${complete ? " cn-done" : ""}`} viewBox={`0 0 ${side} ${side}`} {...svgProps}>
      <defs>
        <clipPath id={`${ids}-hem`}>
          <rect width={side} height={side} rx={radius} />
        </clipPath>
        <pattern id={`${ids}-warn`} patternUnits="userSpaceOnUse" width={U / 2} height={U / 2}>
          <path d={`M${-U / 4} ${U / 4} L${U / 4} ${-U / 4} M0 ${U / 2} L${U / 2} 0 M${U / 4} ${U * 0.75} L${U * 0.75} ${U / 4}`} stroke={REFUSE} stroke-opacity={0.6} stroke-width={U / 18} />
        </pattern>
      </defs>
      <g clip-path={`url(#${ids}-hem)`}>
        <Cloth quilt={quilt} ids={ids} />
        <g aria-hidden="true">
          {lines && <path d={lines} fill={REFUSE} fill-opacity={0.18} />}
          {lines && <path d={lines} fill={`url(#${ids}-warn)`} />}
          {clashes.patches.length > 0 && (
            <path d={patchEdges(quilt, clashes.patches)} stroke={REFUSE} stroke-width={U / 9} stroke-dasharray={`${U / 6} ${U / 9}`} stroke-linecap="round" fill="none" />
          )}
          {xs && <path data-x="" d={xs} stroke="rgba(255,255,255,0.85)" stroke-width={U / 12 + U / 22} stroke-linecap="round" />}
          {xs && <path d={xs} stroke={INK} stroke-width={U / 12} stroke-linecap="round" />}
        </g>
      </g>
      <g aria-hidden="true">
        {state.cells.flatMap((m, cell) => {
          if (m !== 2) return [];
          const clash = clashes.cells.includes(cell);
          const pose: CatPose = complete ? "celebrate" : clash ? "awake" : "asleep";
          const x = (cell % n) * U;
          const y = Math.floor(cell / n) * U;
          return [
            <g key={cell} class="cn-cat" data-cat={cell} style={{ transformOrigin: `${x + U / 2}px ${y + U / 2}px` }}>
              {clash && (
                <circle cx={x + U / 2} cy={y + U / 2} r={U * 0.46} fill="rgba(255,255,255,0.55)" stroke={REFUSE} stroke-width={U / 12} stroke-dasharray={`${U / 8} ${U / 14}`} />
              )}
              <image href={catArt(catFor(quilt.patches[cell]!), pose)} x={x + U * 0.07} y={y + U * 0.07} width={U * 0.86} height={U * 0.86} />
              {state.hinted.includes(cell) && <image data-hinted="" href={art("icon-padlock")} x={x + U * 0.65} y={y + U * 0.65} width={U * 0.3} height={U * 0.3} />}
            </g>,
          ];
        })}
      </g>
      <rect class="cn-binding" width={side} height={side} rx={radius} fill="none" stroke-width={Math.min(U / 8, 7 * (side / 360))} />
      {children}
    </svg>
  );
}

/** The cats so far, as beds: a cat for each one placed with no rule broken, an empty bed for each still to find. */
export function Beds({ n, placed }: { n: number; placed: number }) {
  return (
    <div class="cn-beds" role="img" aria-label={`${placed} of ${n} cats`}>
      {Array.from({ length: n }, (_, i) => (
        <span key={i} class="cn-bed">{i < placed && <img src={catArt(catFor(i), "asleep")} alt="" />}</span>
      ))}
    </div>
  );
}
