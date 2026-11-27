# Toy Tumble on real networks

Design §6.7 and §9.5. Measured on 2026-11-26 against production (`https://play.conleychaos.com`).
At the time `tumble` was in `GAMES` but hidden from every app: the web player's build flag was
off, and iOS and tvOS apps below 1.4 never get it. So the only tables were the tool's own.

## How

`pnpm --filter @pounce/play-api latency:tumble -- --base https://play.conleychaos.com --players N --seconds 60`
(`apps/play-api/scripts/tumble-latency.ts`). N scripted players sit at one table, all run on the
machine that runs the tool, so every number shares one clock and needs no alignment. The players
set down a toy every 0.7 s with the House Cat placer, use any trick they hold on the next seat,
and ack their hits.

The numbers are p50 / p95 / max in ms:
- **rtt:** a ping to the room and back.
- **relay:** a set-down sent, to the next seat hearing it relayed. This is what a TV or a mini box
  waits, so it stands for TV lag.
- **hit:** a set-down that sends junk, or a trick used, to its target hearing the hit.

Each relay and hit is two trips through the internet between that machine and the room's Durable
Object: one in, one out. The GitHub run uses `.github/workflows/tumble-latency.yml`, started by hand.

## Results

| Where | Edge | Players | rtt | relay (TV lag) | hit |
| --- | --- | --- | --- | --- | --- |
| This Mac, home internet | SJC | 3 | 63 / 70 / 290 | 52 / 69 / 89 | 52 / 66 / 74 |
| This Mac, home internet | SJC | 6 | 59 / 73 / 288 | 49 / 70 / 89 | 48 / 73 / 73 |
| GitHub Actions runner | SEA | 3 | 28 / 30 / 37 | 28 / 31 / 33 | 29 / 32 / 33 |

**Targets (§6.7):**
- Hit delivery p95 must be under 250 ms. Measured: 32 to 73 ms. **Passes.**
- TV lag p95 must be under 200 ms. Measured: 31 to 70 ms. **Passes.**

The room's own work adds well under a millisecond. The local run against `wrangler dev` measured
1 ms round-trips, and the soak (§9.3) measured 0.26 ms of CPU per second of round with 6 House
Cats.

## What this doesn't cover

- **Distance.** Both places are on the US West Coast, and GitHub doesn't let a workflow pick its
  runner's region. A Durable Object lives near whoever made the table, so a cousin on the East
  Coast at a West Coast table adds about 70 ms each way. Their hits would arrive in about 150 ms
  at p95, still under the target. Their own box is never affected.
- **Cellular.** Not measured: no phone was there to drive from this session. Cross-play on the
  iPhone simulator ran against a local server, not a mobile network. Measure it by hand from a
  phone on cellular once the game is in the browser.
- **Bad Wi-Fi.** A loss burst looks like a quiet device: "Reconnecting" at 3 s, out at 15 s
  (§6.6). The cross-play run covered a reload and a relaunch, not packet loss.
