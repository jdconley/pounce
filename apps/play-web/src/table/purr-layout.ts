/**
 * How the drawer's screen fits (design §11.2): the word and clock on top, the 3:4 easel as big as
 * what's left allows, then the palette, the tools and Got it / Give up. On a wide window (a tablet
 * on its side, a laptop) the tools stand in a column beside the easel. iPhone SE is the hard case.
 * Pure: the screen sizes its easel from the box it measures, and this says what that box will be.
 */
import { fitEasel } from "./purr-easel";

export const GUTTER = 12;
/** Room the paw menu takes at the top right. */
export const MENU = 56;

export type DrawLayout = {
  /** Tools beside the easel, not under it. */
  side: boolean;
  /** One palette swatch, px. */
  swatch: number;
  /** The rows' heights, px, at this text size. */
  bar: number;
  palette: number;
  tools: number;
  actions: number;
  /** The easel the rest leaves room for. */
  easel: { width: number; height: number };
};

/** `text`: the reader's text size against the default (2 at 200%). `safeTop`, `safeBottom`: the safe-area insets. */
export function drawLayout(w: number, h: number, text = 1, safeTop = 0, safeBottom = 0): DrawLayout {
  const side = w >= h * 0.9 && w >= 600;
  const t = Math.min(Math.max(text, 1), 2.4);
  const bar = Math.round(Math.max(52, 26 * t + 22));
  const tools = Math.round(Math.max(48, 17 * t + 26));
  const actions = Math.round(Math.max(56, 19 * t + 32));
  if (side) {
    const column = Math.min(360, Math.max(240, w * 0.3));
    const easel = fitEasel(w - column - GUTTER * 3, h - safeTop - safeBottom - bar - GUTTER * 2);
    const swatch = Math.max(36, Math.min(56, Math.floor((column - 4 * 8) / 5)));
    return { side, swatch, bar, palette: swatch * 2 + 16, tools, actions, easel };
  }
  const swatch = Math.max(28, Math.min(48, Math.floor((w - GUTTER * 2 - 8 * 6) / 9)));
  const palette = swatch + 8;
  const gaps = GUTTER * 5;
  const easel = fitEasel(w - GUTTER * 2, h - safeTop - safeBottom - bar - palette - tools - actions - gaps);
  return { side, swatch, bar, palette, tools, actions, easel };
}
