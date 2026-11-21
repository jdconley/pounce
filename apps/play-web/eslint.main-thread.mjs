/**
 * The web player's rendering thread does UI work only (docs/main-thread.md): nothing on it may
 * block on IO or run long. Enforced here, statically; e2e/main-thread.spec.ts checks it at run
 * time. Loaded by the root eslint.config.mjs.
 *
 * - No synchronous storage, cookies, sync XHR or modal dialogs anywhere on the page's thread.
 *   Storage lives in one module (src/lib/kv.ts) that reads once and writes in idle time.
 * - No timers in screen and table code: animation runs on requestAnimationFrame, CSS or the Web
 *   Animations API, timed in milliseconds, never in frames. Timers that aren't animation (network
 *   timeouts, pacing) live in net/ and store/.
 * - No frame-counted timing: a 60 Hz frame (16.7 ms, 1000 / 60) is never written into screen or
 *   table code; animation is timed in milliseconds and runs as smoothly at 120 Hz.
 * - No search code on the page's thread: the move solvers and the House Cat run in a Web Worker
 *   (src/workers). Types from those modules are fine.
 */
const PLAY_WEB = "apps/play-web/src";

/** What may never run on the rendering thread. */
const BLOCKING_GLOBALS = [
  { name: "localStorage", message: "Synchronous disk access: use store from src/lib/kv.ts (read once, written in idle time)." },
  { name: "sessionStorage", message: "Synchronous disk access: use store from src/lib/kv.ts." },
  { name: "XMLHttpRequest", message: "Use fetch: it never blocks the rendering thread." },
  { name: "alert", message: "A modal dialog stops the rendering thread: use a Sheet." },
  { name: "confirm", message: "A modal dialog stops the rendering thread: use a Sheet." },
  { name: "prompt", message: "A modal dialog stops the rendering thread: use a Sheet." },
  { name: "importScripts", message: "Synchronous script loading: workers use ES modules." },
];

const BLOCKING_PROPERTIES = [
  ...["window", "globalThis", "self"].flatMap((object) => [
    { object, property: "localStorage", message: "Synchronous disk access: use store from src/lib/kv.ts." },
    { object, property: "sessionStorage", message: "Synchronous disk access: use store from src/lib/kv.ts." },
    { object, property: "alert", message: "A modal dialog stops the rendering thread: use a Sheet." },
    { object, property: "confirm", message: "A modal dialog stops the rendering thread: use a Sheet." },
    { object, property: "prompt", message: "A modal dialog stops the rendering thread: use a Sheet." },
  ]),
  { object: "document", property: "cookie", message: "Cookies are synchronous storage, and Pounce sets none." },
  { object: "Atomics", property: "wait", message: "Blocks the thread: never on the rendering thread." },
];

const ANIMATION_TIMERS = [
  { name: "setTimeout", message: "Screen and table code animates with requestAnimationFrame, CSS or element.animate(), timed in ms; a timer that isn't animation belongs in net/ or store/." },
  { name: "setInterval", message: "Screen and table code animates with requestAnimationFrame, CSS or element.animate(); never poll on the rendering thread." },
];

const TIMER_PROPERTIES = ["window", "globalThis", "self"].flatMap((object) =>
  ["setTimeout", "setInterval"].map((property) => ({ object, property, message: "No timers in screen and table code: see docs/main-thread.md." })),
);

const HEAVY_IMPORTS = {
  patterns: [
    {
      group: ["@pounce/play-api/bots/*", "@pounce/play-api/rules/solver", "@pounce/play-api/tiles/solver", "@pounce/play-api/games/*"],
      allowTypeImports: true,
      message: "Move search runs in a Web Worker (src/workers), never on the rendering thread.",
    },
  ],
};

/** A 60 Hz frame written down as a number is a frame-counted assumption a 120 Hz screen breaks. */
const NO_FRAME_ASSUMPTIONS = [
  {
    selector: "Literal[raw=/^16\\.6|^16\\.7|^33\\.3/]",
    message: "Never assume a 60 Hz frame: time animation in ms (element.animate, CSS) and read frame times, don't hard-code them.",
  },
  {
    selector: "BinaryExpression[operator='/'][left.value=1000][right.value=60]",
    message: "Never assume a 60 Hz frame: time animation in ms (element.animate, CSS).",
  },
];

const UI_CODE = [
  `${PLAY_WEB}/ui/**/*.{ts,tsx}`,
  `${PLAY_WEB}/table/**/*.{ts,tsx}`,
  // The Daily Dish's screens and every game's board; its network code (client, socket, store) keeps its timers.
  `${PLAY_WEB}/daily/**/*.tsx`,
  `${PLAY_WEB}/app.tsx`,
  `${PLAY_WEB}/main.tsx`,
];
/** Not the page's thread: the service worker and Web Workers. */
const OFF_THREAD = [`${PLAY_WEB}/sw.ts`, `${PLAY_WEB}/workers/*.worker.ts`];

export default [
  {
    files: [`${PLAY_WEB}/**/*.{ts,tsx}`],
    ignores: [...OFF_THREAD, `${PLAY_WEB}/lib/kv.ts`],
    rules: {
      "no-restricted-globals": ["error", ...BLOCKING_GLOBALS],
      "no-restricted-properties": ["error", ...BLOCKING_PROPERTIES],
      "no-restricted-imports": ["error", HEAVY_IMPORTS],
    },
  },
  {
    // The one module that may touch storage, and only localStorage.
    files: [`${PLAY_WEB}/lib/kv.ts`],
    rules: {
      "no-restricted-globals": ["error", ...BLOCKING_GLOBALS.filter((g) => g.name !== "localStorage")],
      "no-restricted-properties": ["error", ...BLOCKING_PROPERTIES.filter((p) => p.property !== "localStorage")],
      "no-restricted-imports": ["error", HEAVY_IMPORTS],
    },
  },
  {
    files: UI_CODE,
    rules: {
      "no-restricted-globals": ["error", ...BLOCKING_GLOBALS, ...ANIMATION_TIMERS],
      "no-restricted-properties": ["error", ...BLOCKING_PROPERTIES, ...TIMER_PROPERTIES],
      "no-restricted-syntax": ["error", ...NO_FRAME_ASSUMPTIONS],
    },
  },
];
