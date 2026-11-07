import type { SeatLink } from "../protocol";

/** How often the app sends `{"t":"ping"}` once a snapshot says the server takes them. */
export const LINK_PING_MS = 3000;
/** No ping or message for this long: the device's link is weak (two heartbeats missed). */
export const WEAK_AFTER_MS = 7000;
/** No ping or message for this long: the device is stuck, as good as gone. */
export const LOST_AFTER_MS = 15_000;
/** A socket that dropped without saying goodbye shows as reconnecting for this long. */
export const DROPPED_FOR_MS = 60_000;

const RANK: Record<SeatLink, number> = { weak: 1, lost: 2 };

/**
 * Each device's connection quality, as the room sees it (not persisted: a
 * restart forgets it, and the next pings refill it). A connected device is
 * weak when it said so or has been silent `WEAK_AFTER_MS`, lost once silent
 * `LOST_AFTER_MS`. A device whose socket dropped (not a close it asked for)
 * is lost for `DROPPED_FOR_MS`, then simply away, as presence already says.
 */
export class LinkTracker {
  private readonly heard = new Map<string, number>();
  private readonly weak = new Set<string>();
  private readonly dropped = new Map<string, number>();
  /** The seats' links as last sent to the room. */
  private shown: (SeatLink | null)[] = [];

  connected(deviceId: string, now: number): void {
    this.heard.set(deviceId, now);
    this.weak.delete(deviceId);
    this.dropped.delete(deviceId);
  }

  /** `asked`: the app closed the socket itself (code 1000 or 1001), so nobody is waiting on it. */
  disconnected(deviceId: string, now: number, asked: boolean): void {
    this.heard.delete(deviceId);
    this.weak.delete(deviceId);
    if (asked) this.dropped.delete(deviceId);
    else this.dropped.set(deviceId, now);
  }

  /**
   * A ping (or any message) from a connected device at `at`; older news never
   * moves it back. A device first heard this way (the room just woke) counts as connected.
   */
  hear(deviceId: string, at: number): void {
    const last = this.heard.get(deviceId);
    if (last === undefined || at > last) this.heard.set(deviceId, at);
  }

  /** The app's own view of its link (`{t:"link"}`). */
  report(deviceId: string, weak: boolean): void {
    if (!this.heard.has(deviceId)) return;
    if (weak) this.weak.add(deviceId);
    else this.weak.delete(deviceId);
  }

  /** One device's link now: null when fine, or when it is simply away. */
  device(deviceId: string, now: number): SeatLink | null {
    const heard = this.heard.get(deviceId);
    if (heard === undefined) {
      const at = this.dropped.get(deviceId);
      return at !== undefined && now - at < DROPPED_FOR_MS ? "lost" : null;
    }
    const silent = now - heard;
    if (silent >= LOST_AFTER_MS) return "lost";
    return silent >= WEAK_AFTER_MS || this.weak.has(deviceId) ? "weak" : null;
  }

  /**
   * A seat's link from the devices that control it: the best of those that
   * are connected or just dropped. A seat with none of those has no link to
   * show (its presence says away or asleep).
   */
  seat(devices: string[], now: number): SeatLink | null {
    let best: SeatLink | null | undefined;
    for (const id of devices) {
      if (!this.heard.has(id) && !this.dropped.has(id)) continue;
      const link = this.device(id, now);
      if (best === undefined || rank(link) < rank(best)) best = link;
    }
    return best ?? null;
  }

  /** Records `seats` as shown; true when that changed what the room was last told. */
  show(seats: (SeatLink | null)[]): boolean {
    // A seat never shown counts as fine: a lobby compacting into a game changes nothing.
    const changed = seats.some((s, i) => s !== (this.shown[i] ?? null));
    this.shown = seats;
    return changed;
  }

  /** When some device's link next changes on its own (silence growing, a drop expiring), or null. */
  nextChange(now: number): number | null {
    const times: number[] = [];
    for (const [id, at] of this.heard) {
      const silent = now - at;
      if (silent < WEAK_AFTER_MS && !this.weak.has(id)) times.push(at + WEAK_AFTER_MS);
      else if (silent < LOST_AFTER_MS) times.push(at + LOST_AFTER_MS);
    }
    for (const at of this.dropped.values()) {
      if (now - at < DROPPED_FOR_MS) times.push(at + DROPPED_FOR_MS);
    }
    return times.length === 0 ? null : Math.min(...times);
  }
}

const rank = (link: SeatLink | null): number => (link === null ? 0 : RANK[link]);
