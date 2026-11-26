import { describe, expect, it } from "vitest";

import { newBox, restingY, type Box } from "./box";
import { fromText } from "./codec";
import { toyAt } from "./queue";
import { ACK_MS, DROP_MS, LAG_MS, OWED_MS, STALL_MS, TumbleRound, type RoundOut, type RoundSeat } from "./round";

import type { HitWire, TumbleClient, TumbleRelay, TumbleSync } from "./wire";
import type { Seed } from "../rules/rng";

const SEED: Seed = [7, 7, 7, 7];
const T0 = 1_000_000;
const nFor = (toy: string, from = 0): number => {
  for (let n = from; n < from + 64; n++) if (toyAt(SEED, n) === toy) return n;
  throw new Error(toy);
};
const notch = (k: number): string[] => Array.from({ length: k }, () => ".###########");

function round(kinds: RoundSeat["kind"][] = ["human", "human"], boxes?: Box[]): TumbleRound {
  return new TumbleRound({
    r: 1,
    seats: kinds.map((kind) => ({ kind })),
    roundSeed: SEED,
    trickSeeds: kinds.map((_, i) => [i + 1, 2, 3, 4] as Seed),
    startsAt: T0,
    rng: [9, 9, 9, 9],
    ...(boxes ? { boxes } : {}),
  });
}

const batch = (...ev: TumbleClient["ev"]): TumbleClient => ({ t: "tumble", r: 1, ev });
/** A legal set-down of the box's toy in hand: the first column it rests in. */
function drop(r: TumbleRound, seat: number, ms = 1000): TumbleClient["ev"][number] {
  const b = r.box(seat);
  const toy = toyAt(SEED, b.next);
  for (let x = -2; x < 12; x++) {
    const y = restingY(b, toy, 0, x);
    if (y !== null) return ["l", b.next, 0, x, y, ms, []];
  }
  throw new Error("nowhere");
}
const hitsIn = (out: RoundOut[]) => out.map((o) => o.message).filter((m): m is HitWire => m.t === "tumbleHit");
const syncs = (out: RoundOut[]) => out.filter((o) => o.message.t === "tumbleSync") as { to: RoundOut["to"]; message: TumbleSync }[];
const relays = (out: RoundOut[]) => out.filter((o) => o.message.t === "tumble") as { to: RoundOut["to"]; message: TumbleRelay }[];
/** Seat 0 holds the long stick over four notched rows: an upright drop clears 4. */
const fourReady = (): Box => ({ ...newBox([1, 2, 3, 4]), ...fromText(notch(4)), next: nFor("i4") });
const clearFour = (r: TumbleRound, ms = 1000) => r.input(0, batch(["l", r.box(0).next, 1, -2, 0, ms, []]), T0 + ms);

describe("relaying", () => {
  it("relays a legal set-down to everyone but the sender, counting up per box", () => {
    const r = round();
    const a = r.input(0, batch(drop(r, 0, 500)), T0 + 500);
    const b = r.input(0, batch(drop(r, 0, 900)), T0 + 900);
    expect(relays(a).map((x) => [x.to, x.message.q])).toEqual([[{ except: 0 }, 1]]);
    expect(relays(b)[0]?.message.q).toBe(2);
  });

  it("holds back moves closer than 66 ms and sends the latest on the clock", () => {
    const r = round();
    const n = r.box(0).next;
    expect(relays(r.input(0, batch(["m", n, 0, 4, 17]), T0 + 100))).toHaveLength(1);
    expect(relays(r.input(0, batch(["m", n, 0, 4, 16]), T0 + 120))).toHaveLength(0);
    expect(relays(r.input(0, batch(["m", n, 0, 4, 15]), T0 + 130))).toHaveLength(0);
    const later = relays(r.tick(T0 + 170));
    expect(later[0]?.message.ev).toEqual([["m", n, 0, 4, 15]]);
  });

  it("drops a batch for another round without a word", () => {
    const r = round();
    expect(r.input(0, { t: "tumble", r: 0, ev: [drop(r, 0)] }, T0 + 10)).toEqual([]);
  });

  it("answers an empty batch with every box", () => {
    const r = round();
    const out = r.input(1, batch(), T0 + 10);
    expect(syncs(out)[0]).toMatchObject({ to: { seat: 1 } });
    expect(syncs(out)[0]?.message.boxes.map((b) => b.s)).toEqual([0, 1]);
  });
});

describe("refusals send the sender its own box and relay nothing", () => {
  it.each([
    ["the wrong toy", (r: TumbleRound) => batch(["l", r.box(0).next + 1, 0, 4, 0, 10, []])],
    ["an ack for no hit", () => batch(["a", 99])],
    ["a trick not held", () => batch(["u", 0, 1])],
  ])("%s", (_, make) => {
    const r = round();
    const out = r.input(0, make(r), T0 + 10);
    expect(relays(out)).toHaveLength(0);
    expect(syncs(out)).toHaveLength(1);
    expect(syncs(out)[0]?.to).toEqual({ seat: 0 });
    expect(syncs(out)[0]?.message.boxes.map((b) => b.s)).toEqual([0]);
  });

  it("relays the good events before a refused one", () => {
    const r = round();
    const out = r.input(0, batch(drop(r, 0, 10), ["a", 99]), T0 + 10);
    expect(relays(out)[0]?.message.ev).toHaveLength(1);
    expect(syncs(out)[0]?.to).toEqual({ seat: 0 });
  });

  it("a set-down clock that goes backwards", () => {
    const r = round();
    r.input(0, batch(drop(r, 0, 2000)), T0 + 2000);
    expect(syncs(r.input(0, batch(drop(r, 0, 1500)), T0 + 2100))).toHaveLength(1);
  });
});

describe("attacks and acks", () => {
  it("a 4-row clear sends 4 junk rows to every other box, one gap, ids counting up", () => {
    const r = round(["human", "human", "cat"], [fourReady(), newBox([2, 2, 2, 2]), newBox([3, 3, 3, 3])]);
    const hits = hitsIn(clearFour(r));
    expect(hits.map((h) => [h.to, h.k, (h.x as { rows: number }).rows])).toEqual([[1, "junk", 4], [2, "junk", 4]]);
    expect(hits[1]?.id).toBe((hits[0]?.id ?? 0) + 1);
    expect((hits[0]?.x as { gap: number }).gap).toBe((hits[1]?.x as { gap: number }).gap);
  });

  it("an ack starts the junk's wait on the server's box", () => {
    const r = round(["human", "human"], [fourReady(), newBox([2, 2, 2, 2])]);
    const [hit] = hitsIn(clearFour(r));
    const out = r.input(1, batch(["a", hit?.id ?? 0]), T0 + 1100);
    expect(relays(out)[0]?.message.ev).toEqual([["a", hit?.id]]);
    expect(r.box(1).waiting).toEqual([{ id: hit?.id, rows: 4, gap: (hit?.x as { gap: number }).gap }]);
  });

  it("applies a hit nobody acknowledged in 3 seconds, tells everyone, and refuses the late ack", () => {
    const r = round(["human", "human"], [fourReady(), newBox([2, 2, 2, 2])]);
    const [hit] = hitsIn(clearFour(r));
    r.input(1, batch(drop(r, 1, 1500)), T0 + 1500);
    const out = r.tick(T0 + 1000 + ACK_MS);
    expect(syncs(out)).toHaveLength(1);
    expect(syncs(out)[0]?.to).toBe("all");
    expect(r.box(1).waiting).toHaveLength(1);
    const late = r.input(1, batch(["a", hit?.id ?? 0]), T0 + 1000 + ACK_MS + 10);
    expect(syncs(late)[0]?.to).toEqual({ seat: 1 });
    expect(r.box(1).waiting).toHaveLength(1);
  });

  it("lands junk a device owes 4 seconds after its ack, and tells everyone", () => {
    const r = round(["human", "human"], [fourReady(), newBox([2, 2, 2, 2])]);
    const [hit] = hitsIn(clearFour(r));
    r.input(1, batch(["a", hit?.id ?? 0]), T0 + 1100);
    const late = T0 + 1100 + OWED_MS + 1;
    const out = r.input(1, batch(drop(r, 1, late - T0)), late);
    expect(syncs(out)[0]?.to).toBe("all");
    expect(r.box(1).waiting).toEqual([]);
    expect(r.box(1).cells.slice(0, 12).filter((c) => c === 10)).toHaveLength(11);
  });
});

describe("tricks", () => {
  const holding = (held: Box["held"]): Box => ({ ...newBox([1, 1, 1, 1]), held });

  it("a trick on a napping box is spent with nothing to apply", () => {
    const r = round(["human", "human"], [holding(["hairball"]), holding(["nap"])]);
    const [nap] = hitsIn(r.input(1, batch(["u", 0, 1]), T0 + 100));
    r.input(1, batch(["a", nap?.id ?? 0]), T0 + 150);
    const out = r.input(0, batch(["u", 0, 1]), T0 + 200);
    expect(hitsIn(out).map((h) => h.k)).toEqual(["napped"]);
    expect(r.box(0).held).toEqual([]);
  });

  it("Swap sends each box the other's contents", () => {
    const a: Box = { ...holding(["swap"]), ...fromText(["1..........."]) };
    const b: Box = { ...newBox([2, 2, 2, 2]), ...fromText(["5555........"]) };
    const r = round(["human", "human"], [a, b]);
    const hits = hitsIn(r.input(0, batch(["u", 0, 1]), T0 + 100));
    expect(hits.map((h) => [h.to, h.k])).toEqual([[1, "swap"], [0, "swap"]]);
    expect((hits[0]?.x as { cells: number[] }).cells[0]).toBe(1);
    expect((hits[1]?.x as { cells: number[] }).cells[0]).toBe(5);
  });

  it("a hit on a box that went out before its ack is void", () => {
    const tall: Box = { ...newBox([2, 2, 2, 2]), ...fromText(Array.from({ length: 17 }, () => "#...........")) };
    const r = round(["human", "human", "human"], [holding(["catnip"]), tall, newBox([3, 3, 3, 3])]);
    const [hit] = hitsIn(r.input(0, batch(["u", 0, 1]), T0 + 100));
    // Seat 1's hairball-free box tops out on its own next set-down.
    const n = r.box(1).next;
    const toy = toyAt(SEED, n);
    const y = restingY(r.box(1), toy, 0, 0);
    if (y === null) throw new Error("no room");
    r.input(1, batch(["l", n, 0, 0, y, 200, []]), T0 + 200);
    expect(r.box(1).out).toBe(true);
    expect(syncs(r.tick(T0 + 100 + ACK_MS + 1))).toHaveLength(0);
    expect(syncs(r.input(1, batch(["a", hit?.id ?? 0]), T0 + 4000))).toHaveLength(0);
  });
});

describe("a box that stops setting down", () => {
  it("gets the junk it owes landed by the server after 25 seconds without a set-down", () => {
    const r = round(["human", "human"], [fourReady(), newBox([2, 2, 2, 2])]);
    const [hit] = hitsIn(clearFour(r));
    r.input(1, batch(["a", hit?.id ?? 0]), T0 + 1100);
    for (let t = T0 + 2000; t < T0 + STALL_MS; t += 1000) {
      r.input(0, batch(), t);
      r.input(1, batch(), t);
      r.tick(t);
    }
    expect(r.box(1).waiting).toHaveLength(1);
    r.input(0, batch(), T0 + STALL_MS);
    r.input(1, batch(), T0 + STALL_MS);
    const out = r.tick(T0 + STALL_MS);
    expect(syncs(out)[0]?.to).toBe("all");
    expect(r.box(1).waiting).toEqual([]);
  });
});

describe("presence", () => {
  it("a quiet device lags at 3 seconds and is out at 15, and junk to a lagging box waits", () => {
    const r = round(["human", "human", "human"], [fourReady(), newBox([2, 2, 2, 2]), newBox([3, 3, 3, 3])]);
    r.input(2, batch(), T0 + 2000);
    r.input(0, batch(), T0 + 2000);
    const lag = r.tick(T0 + LAG_MS);
    expect(lag.map((o) => o.message)).toContainEqual({ t: "tumbleSeat", r: 1, s: 1, st: "lag" });
    const hits = hitsIn(clearFour(r, LAG_MS + 100));
    expect(hits.map((h) => h.to)).toEqual([1, 2]);
    r.input(2, batch(["a", hits[1]?.id ?? 0]), T0 + LAG_MS + 200);
    r.input(0, batch(), T0 + LAG_MS + ACK_MS + 500);
    r.input(2, batch(), T0 + LAG_MS + ACK_MS + 500);
    r.tick(T0 + LAG_MS + ACK_MS + 500);
    expect(r.box(1).waiting).toEqual([]);
    const back = r.input(1, batch(), T0 + 9000);
    expect(back.map((o) => o.message.t)).toEqual(["tumbleSeat", "tumbleSync", "tumbleHit", "tumbleSync"]);
    expect(back[2]?.to).toEqual({ seat: 1 });
  });

  it("a device silent for 15 seconds is out", () => {
    const r = round();
    r.input(0, batch(), T0 + DROP_MS - 1);
    r.tick(T0 + DROP_MS);
    expect(r.box(1).out).toBe(true);
    expect(r.result()).toEqual({ over: true, winner: 0, outs: [1] });
  });
});

describe("the end of a round", () => {
  it("is the last box standing", () => {
    const r = round(["human", "human", "human"]);
    expect(r.result().over).toBe(false);
  });

  it("with no person left, the House Cat that cleared the most rows wins", () => {
    const cat = (rows: number): Box => ({ ...newBox([4, 4, 4, 4]), rows });
    const out: Box = { ...newBox([1, 1, 1, 1]), out: true };
    const r = round(["human", "cat", "cat"], [out, cat(3), cat(7)]);
    expect(r.result()).toMatchObject({ over: true, winner: 2 });
  });

  it("nobody wins when the last boxes go out together", () => {
    const out: Box = { ...newBox([1, 1, 1, 1]), out: true };
    const r = round(["human", "human"], [out, out]);
    expect(r.result()).toMatchObject({ over: true, winner: null });
  });

  it("an away seat never plays", () => {
    const r = round(["human", "away", "human"]);
    expect(r.live(1)).toBe(false);
    expect(r.sync("all", T0).boxes.map((b) => b.s)).toEqual([0, 2]);
  });
});

describe("the room's calls", () => {
  it("drop puts a box out at once, and it can't win", () => {
    const r = round(["human", "human", "human"]);
    expect(syncs(r.drop(1, T0 + 100))[0]?.to).toBe("all");
    expect(r.live(1)).toBe(false);
    expect(r.drop(1, T0 + 200)).toEqual([]);
    r.drop(2, T0 + 300);
    expect(r.result()).toMatchObject({ over: true, winner: 0, outs: [1, 2] });
  });

  it("an older heard time never clears a lag", () => {
    const r = round();
    r.input(0, batch(), T0 + LAG_MS);
    r.tick(T0 + LAG_MS);
    expect(r.heard(1, T0 + 500)).toEqual([]);
    expect(r.sync([1], T0 + LAG_MS).boxes[0]?.status).toBe("lag");
  });

  it("refuses a Swap aimed at your own box, and you keep it", () => {
    const r = round(["human", "human"], [{ ...newBox([1, 1, 1, 1]), held: ["swap"] }, newBox([2, 2, 2, 2])]);
    expect(syncs(r.input(0, batch(["u", 0, 0]), T0 + 100))[0]?.to).toEqual({ seat: 0 });
    expect(r.box(0).held).toEqual(["swap"]);
  });
});
