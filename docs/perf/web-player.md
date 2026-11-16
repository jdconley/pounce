# Web player performance

Measured 15 November 2026 with `apps/play-web/scripts/perf.mjs` (Chrome via Playwright, a practice game against the House Cat on `wrangler dev`, art already cached). Each run records a Chrome DevTools trace (`trace-<profile>.json.gz`, open it in DevTools Performance) and the frame times the page sees with `requestAnimationFrame`. Run it again with:

```bash
BASE=http://127.0.0.1:8790 OUT=perf-out node apps/play-web/scripts/perf.mjs
```

## First load

A mid-range phone (Pixel 7 screen, CPU slowed 4x) over slow 4G (150 ms, 1.6 Mbps), nothing cached:

| First paint | First screen ready | Transferred | Of it, script | Requests |
| --- | --- | --- | --- | --- |
| 660 ms | 669 ms | 36 KB | 24 KB | 4 |

Off Apple devices the rounded font (Nunito, about 20 KB) is fetched too. The lobby and tables (21 KB) load in the background once the first screen is up; the art is cached by the service worker as it is used.

## Laptop (1440x900, 2x)

| Moment | Frames | fps | p50 ms | p95 ms | Longest ms | Dropped (>25 ms) |
| --- | --- | --- | --- | --- | --- | --- |
| deal | 143 | 60 | 16.7 | 16.8 | 16.8 | 0 |
| drag | 218 | 60 | 16.7 | 16.7 | 16.8 | 0 |
| play | 262 | 60 | 16.7 | 16.7 | 16.8 | 0 |
| round end | 239 | 60 | 16.7 | 16.7 | 16.8 | 0 |

Main thread over the whole run: 0 tasks over 50 ms, p95 task 0.3 ms, longest 7.9 ms; 211 layouts and 1022 paints across 2968 frames.

## Mobile (Pixel 7, CPU slowed 4x)

| Moment | Frames | fps | p50 ms | p95 ms | Longest ms | Dropped (>25 ms) |
| --- | --- | --- | --- | --- | --- | --- |
| deal | 144 | 60 | 16.7 | 16.7 | 16.8 | 0 |
| drag | 218 | 60 | 16.7 | 16.7 | 16.8 | 0 |
| play | 384 | 60 | 16.7 | 16.7 | 16.8 | 0 |
| round end | 239 | 60 | 16.7 | 16.8 | 16.8 | 0 |

Main thread over the whole run: 0 tasks over 50 ms, p95 task 1.1 ms, longest 26.5 ms; 205 layouts and 1003 paints across 3034 frames.

## Reading it

- Every moment holds 60 fps with no dropped frames, on the slowed phone too. Cards and pieces move only by `transform` (Web Animations API), so frames are drawn by the compositor and the main thread stays idle: its 95th-percentile task is 0.3 ms on the laptop and 1.1 ms on the slowed phone, well under the 8.3 ms a 120 Hz frame allows.
- Headless Chrome draws at 60 Hz, so 120 Hz is shown by headroom, not counted: nothing on the main thread runs long enough to miss a 120 Hz frame on the laptop.
- Glows (your turn, the pile you can take) are drawn once and only fade, after a first trace showed a box-shadow animation repainting every frame (6,562 paints before, about a seventh of that after).
