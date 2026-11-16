/**
 * The iOS sound effects (`Pounce/Resources/Sounds`), played with Web Audio: each decoded once,
 * started with no delay. Nothing plays before the first tap (browsers' autoplay rule), and
 * nothing at all with sound off.
 */
import { settings } from "./settings";

export type Sfx = "bat" | "fanfare" | "flip" | "leap" | "nope" | "pop" | "scream" | "sparkle" | "thud" | "tick" | "whoosh";

const opus = import.meta.glob("../sound/*.webm", { eager: true, query: "?url", import: "default" }) as Record<string, string>;
const aac = import.meta.glob("../sound/*.m4a", { eager: true, query: "?url", import: "default" }) as Record<string, string>;

let ctx: AudioContext | null = null;
const buffers = new Map<Sfx, Promise<AudioBuffer | null>>();

function canOpus(): boolean {
  try {
    return new Audio().canPlayType('audio/webm; codecs="opus"') !== "";
  } catch {
    return false;
  }
}

function load(name: Sfx): Promise<AudioBuffer | null> {
  let found = buffers.get(name);
  if (!found) {
    const url = (canOpus() ? opus : aac)[`../sound/sfx-${name}.${canOpus() ? "webm" : "m4a"}`];
    found = (async () => {
      if (!ctx || !url) return null;
      try {
        const data = await (await fetch(url)).arrayBuffer();
        return await ctx.decodeAudioData(data);
      } catch {
        return null;
      }
    })();
    buffers.set(name, found);
  }
  return found;
}

/** Called on the first tap or key: browsers let audio start only after one. */
export function unlockAudio(): void {
  if (ctx) {
    if (ctx.state === "suspended") void ctx.resume();
    return;
  }
  const Ctor = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  if (!Ctor) return;
  ctx = new Ctor({ latencyHint: "interactive" });
  for (const name of ["pop", "flip", "whoosh", "thud", "tick", "nope"] as Sfx[]) void load(name);
}

export function play(name: Sfx, volume = 0.8): void {
  if (!settings().sound || !ctx) return;
  const audio = ctx;
  void load(name).then((buffer) => {
    if (!buffer || audio.state !== "running") return;
    const source = audio.createBufferSource();
    source.buffer = buffer;
    const gain = audio.createGain();
    gain.gain.value = volume;
    source.connect(gain).connect(audio.destination);
    source.start();
  });
}
