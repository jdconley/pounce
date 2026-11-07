import { describe, expect, it } from "vitest";

import { DROPPED_FOR_MS, LOST_AFTER_MS, LinkTracker, WEAK_AFTER_MS } from "./link";

const T0 = 1_000_000;

describe("LinkTracker", () => {
  it("is fine right after connecting, weak after two missed heartbeats, lost after fifteen seconds", () => {
    const link = new LinkTracker();
    link.connected("a", T0);
    expect(link.device("a", T0)).toBeNull();
    expect(link.device("a", T0 + WEAK_AFTER_MS - 1)).toBeNull();
    expect(link.device("a", T0 + WEAK_AFTER_MS)).toBe("weak");
    expect(link.device("a", T0 + LOST_AFTER_MS - 1)).toBe("weak");
    expect(link.device("a", T0 + LOST_AFTER_MS)).toBe("lost");
  });

  it("a ping puts it right again; an older ping changes nothing", () => {
    const link = new LinkTracker();
    link.connected("a", T0);
    link.hear("a", T0 + 10_000);
    expect(link.device("a", T0 + 10_000)).toBeNull();
    link.hear("a", T0 + 2000);
    expect(link.device("a", T0 + 10_000 + WEAK_AFTER_MS)).toBe("weak");
  });

  it("a device first heard by a ping (the room just woke) counts as connected", () => {
    const link = new LinkTracker();
    link.hear("a", T0);
    expect(link.device("a", T0 + 1)).toBeNull();
    expect(link.seat(["a"], T0 + LOST_AFTER_MS)).toBe("lost");
  });

  it("takes the app's own report while it is connected", () => {
    const link = new LinkTracker();
    link.report("a", true);
    expect(link.device("a", T0)).toBeNull();
    link.connected("a", T0);
    link.report("a", true);
    expect(link.device("a", T0)).toBe("weak");
    link.report("a", false);
    expect(link.device("a", T0)).toBeNull();
    link.report("a", true);
    link.connected("a", T0 + 1);
    expect(link.device("a", T0 + 1)).toBeNull();
  });

  it("a dropped socket is lost for a minute, then just away; a close the app asked for is away at once", () => {
    const link = new LinkTracker();
    link.connected("a", T0);
    link.report("a", true);
    link.disconnected("a", T0 + 1000, false);
    expect(link.device("a", T0 + 1000)).toBe("lost");
    expect(link.device("a", T0 + 1000 + DROPPED_FOR_MS - 1)).toBe("lost");
    expect(link.device("a", T0 + 1000 + DROPPED_FOR_MS)).toBeNull();

    link.connected("a", T0 + 2000);
    expect(link.device("a", T0 + 2000)).toBeNull();
    link.disconnected("a", T0 + 3000, true);
    expect(link.device("a", T0 + 3000)).toBeNull();
    expect(link.device("never", T0)).toBeNull();
  });

  it("a seat takes the best of its connected or just-dropped devices", () => {
    const link = new LinkTracker();
    expect(link.seat([], T0)).toBeNull();
    expect(link.seat(["unknown"], T0)).toBeNull();
    link.connected("phone", T0);
    link.connected("pad", T0);
    link.disconnected("pad", T0, false);
    expect(link.seat(["phone", "pad"], T0)).toBeNull();
    expect(link.seat(["pad"], T0)).toBe("lost");
    expect(link.seat(["pad", "phone"], T0 + WEAK_AFTER_MS)).toBe("weak");
    expect(link.seat(["pad", "phone"], T0 + LOST_AFTER_MS)).toBe("lost");
  });

  it("tells when the room's view changed", () => {
    const link = new LinkTracker();
    expect(link.show([])).toBe(false);
    expect(link.show([null, null])).toBe(false);
    expect(link.show(["weak"])).toBe(true);
    expect(link.show([null, null])).toBe(true);
    expect(link.show([null, "weak"])).toBe(true);
    expect(link.show([null, "lost"])).toBe(true);
  });

  it("knows when a link next changes by itself", () => {
    const link = new LinkTracker();
    expect(link.nextChange(T0)).toBeNull();
    link.connected("a", T0);
    expect(link.nextChange(T0)).toBe(T0 + WEAK_AFTER_MS);
    expect(link.nextChange(T0 + WEAK_AFTER_MS)).toBe(T0 + LOST_AFTER_MS);
    expect(link.nextChange(T0 + LOST_AFTER_MS)).toBeNull();
    link.report("a", true);
    expect(link.nextChange(T0 + 1)).toBe(T0 + LOST_AFTER_MS);

    link.disconnected("a", T0, false);
    expect(link.nextChange(T0)).toBe(T0 + DROPPED_FOR_MS);
    expect(link.nextChange(T0 + DROPPED_FOR_MS)).toBeNull();
  });
});
