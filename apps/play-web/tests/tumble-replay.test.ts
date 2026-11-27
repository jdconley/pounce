/**
 * Every other box, replayed from what the server relays (spec §6.4 to §6.6): the engine's golden
 * streams, sent as relays, hits and acks, give exactly the boxes the engine does; hits wait for
 * the target's ack; a gap or a refused event asks for a sync and replays nothing out of order.
 */
import { readdirSync, readFileSync } from "node:fs";

import { newBox } from "@pounce/play-api/tumble/box";
import { toyAt } from "@pounce/play-api/tumble/queue";
import { spawn } from "@pounce/play-api/tumble/toys";
import { boxFromExpect, hitFromText, type VectorFile } from "@pounce/play-api/tumble/vectors";
import { describe, expect, test } from "vitest";

import { Replay } from "../src/tumble/replay";

import type { Seed } from "@pounce/play-api/rules/rng";
import type { ClientEvent, HitWire, TumbleServer } from "@pounce/play-api/tumble/wire";

const DIR = new URL("../../play-api/fixtures/tumble/", import.meta.url);
const files = readdirSync(DIR)
  .filter((f) => f.endsWith(".json"))
  .map((f) => JSON.parse(readFileSync(new URL(f, DIR), "utf8")) as VectorFile);

const SEAT = 1;
const relay = (q: number, ev: ClientEvent[]): TumbleServer => ({ t: "tumble", r: 1, s: SEAT, q, ev });

describe("replaying the engine's golden streams from the wire", () => {
  test.each(files.filter((f) => f.steps.some((s) => s.do[0] !== "turn")))("$name", (v) => {
    const replay = new Replay({ r: 1, roundSeed: v.roundSeed, trickSeeds: [v.trickSeed, v.trickSeed], seats: [SEAT], startsAt: 0, now: () => 0 });
    if (v.start) replay.apply({ t: "tumbleSync", r: 1, boxes: [{ s: SEAT, box: boxFromExpect(v.start), q: 0, waitingLeft: [], catnipLeft: 0, napLeft: 0, status: "ok" }] });
    let q = 0;
    let id = 1000;
    for (const step of v.steps) {
      const op = step.do;
      // A refused event is never relayed: the server sends its sender a sync instead.
      if ("error" in step.expect) continue;
      if (op[0] === "turn") continue;
      if (op[0] === "setDown") replay.apply(relay(++q, [["l", op[1], op[2], op[3], op[4], 1000, op[5]]]));
      else if (op[0] === "use") replay.apply(relay(++q, [["u", op[1], 0]]));
      else if (op[0] === "junk") {
        replay.apply({ t: "tumbleHit", r: 1, id: op[1].id, from: 0, to: SEAT, k: "junk", x: { rows: op[1].rows, gap: op[1].gap } });
        replay.apply(relay(++q, [["a", op[1].id]]));
      } else {
        const hit = hitFromText(op[1]);
        const { k, ...x } = hit;
        const wire: HitWire = { t: "tumbleHit", r: 1, id: ++id, from: 0, to: SEAT, k, ...(Object.keys(x).length > 0 ? { x } : {}) };
        replay.apply(wire);
        replay.apply(relay(++q, [["a", wire.id]]));
      }
      expect(replay.needsSync(), `${v.name} ${JSON.stringify(op).slice(0, 80)}`).toBe(false);
      expect(replay.box(SEAT)).toEqual(boxFromExpect((step.expect as { box: Parameters<typeof boxFromExpect>[0] }).box));
    }
  });
});

describe("the stream", () => {
  const seed: Seed = [1, 2, 3, 4];
  const make = () => new Replay({ r: 3, roundSeed: seed, trickSeeds: [seed, [9, 9, 9, 9], seed], seats: [0, 1, 2], startsAt: 0, now: () => 500 });

  test("a hit waits for the target's ack, in the target's order", () => {
    const replay = make();
    replay.apply({ t: "tumbleHit", r: 3, id: 5, from: 0, to: 1, k: "hairball", x: { gap: 2 } });
    expect(replay.box(1)).toEqual(newBox([9, 9, 9, 9]));
    replay.apply({ t: "tumble", r: 3, s: 1, q: 1, ev: [["a", 5]] });
    expect(replay.box(1)!.cells.slice(0, 12)).toEqual([10, 10, 0, 10, 10, 10, 10, 10, 10, 10, 10, 10]);
    expect(replay.needsSync()).toBe(false);
  });

  test("a gap in q asks for a sync, and nothing after it replays until the sync comes", () => {
    const replay = make();
    const toy = toyAt(seed, 0);
    const at = spawn(toy);
    replay.apply({ t: "tumble", r: 3, s: 2, q: 1, ev: [["m", 0, 0, at.x, 10]] });
    expect(replay.needsSync()).toBe(false);
    replay.apply({ t: "tumble", r: 3, s: 2, q: 3, ev: [["m", 0, 0, at.x, 5]] });
    expect(replay.needsSync()).toBe(true);
    expect(replay.toy(2)?.y).toBe(10);
    replay.apply({ t: "tumble", r: 3, s: 2, q: 4, ev: [["m", 0, 0, at.x, 4]] });
    expect(replay.toy(2)?.y).toBe(10);
    replay.apply({ t: "tumbleSync", r: 3, boxes: [{ s: 2, box: newBox(seed), q: 4, waitingLeft: [], catnipLeft: 0, napLeft: 0, status: "ok" }] });
    expect(replay.needsSync()).toBe(false);
    replay.apply({ t: "tumble", r: 3, s: 2, q: 5, ev: [["m", 0, 0, at.x, 3]] });
    expect(replay.toy(2)?.y).toBe(3);
  });

  test("a duplicate relay is ignored, and a set-down the engine refuses asks for a sync", () => {
    const replay = make();
    replay.apply({ t: "tumble", r: 3, s: 0, q: 1, ev: [["u", 0, 1]] });
    expect(replay.needsSync()).toBe(true);
    const fresh = make();
    fresh.apply({ t: "tumble", r: 3, s: 0, q: 1, ev: [["l", 0, 0, 5, 9, 100, []]] });
    expect(fresh.needsSync()).toBe(true);
  });

  test("another round's messages are dropped", () => {
    const replay = make();
    replay.apply({ t: "tumble", r: 2, s: 0, q: 9, ev: [] });
    expect(replay.needsSync()).toBe(false);
  });

  test("a lagging seat shows it, and its toy hangs still", () => {
    const replay = make();
    replay.apply({ t: "tumbleSeat", r: 3, s: 1, st: "lag" });
    expect(replay.view(1, 500)?.status).toBe("lag");
    replay.apply({ t: "tumbleSeat", r: 3, s: 1, st: "ok" });
    expect(replay.view(1, 500)?.status).toBe("ok");
  });

  test("a falling toy glides between position updates by the box's gravity, at most a row, never past where it lands", () => {
    const replay = new Replay({ r: 3, roundSeed: seed, trickSeeds: [seed], seats: [0], startsAt: 0, now: () => 0 });
    const at = spawn(toyAt(seed, 0));
    replay.apply({ t: "tumble", r: 3, s: 0, q: 1, ev: [["m", 0, 0, at.x, 10]] });
    expect(replay.view(0, 0)!.toy!.y).toBe(10);
    expect(replay.view(0, 500)!.toy!.y).toBeCloseTo(9.5);
    expect(replay.view(0, 60_000)!.toy!.y).toBe(9);
    const landing = replay.view(0, 0)!.landing;
    replay.apply({ t: "tumble", r: 3, s: 0, q: 2, ev: [["m", 0, 0, at.x, landing]] });
    expect(replay.view(0, 900)!.toy!.y).toBe(landing);
  });
});
