/**
 * The shared live layer's rate limit (Toy Tumble design §6.10): at most `perSecond` messages a
 * second per key (a device), over any rolling second. In memory only, like everything it guards.
 * Each game keeps its own messages, checks and fan-out; this knows nothing about any of them.
 */
export class LiveRelay {
  private readonly perSecond: number;
  private readonly sent = new Map<string, number[]>();

  constructor(perSecond: number) {
    this.perSecond = perSecond;
  }

  /** True, and counted, when `key` may send one more at `now`; false when it is over its limit. */
  allow(key: string, now: number): boolean {
    const recent = (this.sent.get(key) ?? []).filter((at) => at > now - 1000);
    if (recent.length >= this.perSecond) {
      this.sent.set(key, recent);
      return false;
    }
    recent.push(now);
    this.sent.set(key, recent);
    return true;
  }

  /** Forgets every key: a new round starts everyone afresh. */
  clear(): void {
    this.sent.clear();
  }
}
