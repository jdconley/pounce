/**
 * The live table (§11.3): a Live Activity for a live stretch of play, started
 * by push-to-start when you leave a table someone else is at, updated on each
 * turn change, and ended by the round, your return, 30 minutes with no move,
 * or 2 hours. The pure rules and the APNs bodies; `RoomCore` keeps the records
 * and `DeviceIndex` the tokens.
 */

/** No move at the table for this long ends it (§11.3). */
export const IDLE_MS = 30 * 60_000;
/** The hard cap per activity (§11.3). */
export const CAP_MS = 2 * 60 * 60_000;
/** A missed push still greys it out: last update + 30 minutes (§11.3). */
export const STALE_MS = 30 * 60_000;
/** Answering Play to a pounce makes the table live for you for this long (§11.3). */
export const POUNCE_LIVE_MS = 60 * 60_000;
/** The Swift `ActivityAttributes` type the app declares; push-to-start names it. */
export const ATTRIBUTES_TYPE = "LiveTableAttributes";
/** The House Cat bot is drawn as cat 3 with the bot badge, as in the app. */
const BOT_CAT = 3;
const BOT_NAME = "House Cat";
const FINAL_PHASE = 10;

/** One seat on the rug strip: its cat, the phase it's working on (1–10), and whether this device holds it. */
export type LiveSeat = { cat: number; phase: number; name?: string; bot: boolean; me: boolean };

/**
 * The Live Activity's `content-state`, from one device's point of view. The
 * app's `LiveTableState` decodes exactly this (`fixtures/push/live-activity.json`).
 */
export type LiveState = {
  table: string;
  seats: LiveSeat[];
  /** Whose move it is, or null between rounds. */
  turn: number | null;
  /** The move is one of this device's seats: the bell. */
  mine: boolean;
  /** The device player's pair at this table: the numeral and today's paws. */
  streak: { count: number; me: boolean; them: boolean } | null;
};

/** One device's live table at a room. */
export type LiveRecord = { startedAt: number; movedAt: number };

export type LiveAlert = { title: string; body: string };

/** When the live table ends by itself: the idle limit or the cap, whichever is first. */
export const deadline = (r: LiveRecord): number => Math.min(r.movedAt + IDLE_MS, r.startedAt + CAP_MS);

/** Which limit has passed, if any. */
export function expired(r: LiveRecord, now: number): "idle" | "cap" | null {
  if (now < deadline(r)) return null;
  return r.startedAt + CAP_MS <= now ? "cap" : "idle";
}

type SeatIn = { kind: string; person?: { name: string; cat: number } };

/** The content state for a device controlling `controlled`, from the room's seats and phases. */
export function liveState(i: {
  table: string;
  seats: SeatIn[];
  phases: number[];
  controlled: number[];
  turn: number | null;
  streak: LiveState["streak"];
}): LiveState {
  const seats = i.seats.map((s, n): LiveSeat => {
    const phase = Math.min((i.phases[n] ?? 0) + 1, FINAL_PHASE);
    const me = i.controlled.includes(n);
    return s.kind === "bot" || !s.person
      ? { cat: BOT_CAT, phase, bot: true, me }
      : { cat: s.person.cat, phase, name: s.person.name, bot: false, me };
  });
  return { table: i.table, seats, turn: i.turn, mine: i.turn !== null && i.controlled.includes(i.turn), streak: i.streak };
}

const seconds = (ms: number) => Math.floor(ms / 1000);

/** APNs needs an alert to start an activity; this one makes no sound (you just left the table). */
export function startAlert(s: LiveState): LiveAlert {
  if (s.turn === null) return { title: s.table, body: s.table };
  if (s.mine) return { title: s.table, body: "Your move." };
  const seat = s.seats[s.turn];
  return { title: s.table, body: `${seat?.name ?? BOT_NAME}'s move.` };
}

/** Push-to-start (§11.3): the attributes, a request for the activity's update token, and the stale date. */
export function startBody(code: string, s: LiveState, now: number, alert: LiveAlert): Record<string, unknown> {
  return {
    aps: {
      timestamp: seconds(now),
      event: "start",
      "content-state": s,
      "attributes-type": ATTRIBUTES_TYPE,
      attributes: { code },
      "input-push-token": 1,
      "stale-date": seconds(now + STALE_MS),
      alert,
    },
  };
}

/** A turn change; `alert` (with the turn sound) only when the move comes to this device. */
export function updateBody(s: LiveState, now: number, alert: LiveAlert | null): Record<string, unknown> {
  return {
    aps: {
      timestamp: seconds(now),
      event: "update",
      "content-state": s,
      "stale-date": seconds(now + STALE_MS),
      ...(alert ? { alert: { ...alert, sound: "default" } } : {}),
    },
  };
}

/** Ends it and takes it off the Lock Screen now. */
export function endBody(s: LiveState, now: number): Record<string, unknown> {
  return { aps: { timestamp: seconds(now), event: "end", "content-state": s, "dismissal-date": seconds(now) } };
}
