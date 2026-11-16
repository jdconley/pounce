/** The web player's art (built by scripts/build-art.mjs from the iOS asset catalog), by name. */
const files = import.meta.glob("../art/*.webp", { eager: true, query: "?url", import: "default" }) as Record<string, string>;

export const art = (name: string): string => files[`../art/${name}.webp`] ?? "";

export type CatPose = "idle" | "awake" | "away" | "asleep" | "celebrate" | "leap" | "terrified";

export const catArt = (cat: number, pose: CatPose = "idle"): string => art(`cat${Math.min(Math.max(Math.trunc(cat) || 0, 0), 7)}-${pose}`);

/** The cats' names, for screen readers. */
export const CAT_NAMES = ["Ginger", "Tuxedo", "Calico", "Gray", "Black", "White", "Siamese", "Tortie"] as const;

/** Seat ring colours, in seat order (iOS `Palette.playerRings`). */
export const RINGS = ["#7B2FFF", "#FF2E9A", "#00D1C1", "#FF8A00", "#2EB8FF", "#9BE22E"] as const;

/** Starts fetching images the next screen draws, so they are decoded when it shows. */
export function preload(names: string[]): void {
  for (const name of names) {
    const url = art(name);
    if (!url) continue;
    const img = new Image();
    img.decoding = "async";
    img.src = url;
  }
}
