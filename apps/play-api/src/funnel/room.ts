/**
 * The funnel steps a table can vouch for (first-run funnel design, Part 3): who holds a seat,
 * who joined someone else's table, a device's first move, and a finished game, with whom.
 */

import type { Reached } from "./funnel";
import type { SeatInfo } from "../room/core";

/** What of a room's state the steps are read from. */
export type RoomFacts = {
  game: string;
  hostDeviceId: string;
  status: string;
  seats: readonly SeatInfo[];
  /** Null while the table is a lobby that was never dealt. */
  gameState: unknown;
};

/**
 * The steps `facts` shows that `told` doesn't hold yet, after `moved` (a device whose move the
 * room just accepted, if any). Adds them to `told`, so a room reports each device's step once
 * while it stays awake; the database keeps the first time anyway.
 */
export function roomSteps(facts: RoomFacts, told: Set<string>, moved: string | null): Reached[] {
  const seated = facts.seats.flatMap((s) => (s.kind === "human" && s.deviceId ? [s.deviceId] : []));
  const devices = [...new Set(seated)];
  const steps: Reached[] = [];
  const add = (deviceId: string, milestone: Reached["milestone"]) => {
    const key = `${deviceId}:${milestone}`;
    if (told.has(key)) return;
    told.add(key);
    steps.push({ deviceId, milestone, game: facts.game });
  };
  for (const deviceId of devices) {
    add(deviceId, "seat_taken");
    if (deviceId !== facts.hostDeviceId) add(deviceId, "joined_table");
  }
  if (moved !== null) add(moved, "first_move");
  if (facts.status === "over" && facts.gameState !== null) {
    for (const deviceId of devices) {
      add(deviceId, "game_finished");
      if (seated.length >= 2) add(deviceId, "game_with_human");
      if (devices.length >= 2) add(deviceId, "game_with_device");
    }
  }
  return steps;
}
