import { describe, expect, test } from "vitest";

import {
  allows,
  attemptAllowed,
  confirm,
  expireText,
  FAIL_WINDOW_MS,
  isStop,
  KID,
  LINK_CODE,
  link,
  MAX_FAILS,
  newKid,
  newLinkCode,
  newRecord,
  nextWake,
  normalizePhone,
  parentState,
  approvedSet,
  repointParent,
  repointPartner,
  revoke,
  secondSent,
  secondTextAt,
  setAppleApprovals,
  setParentApprovals,
  text,
  TEXTED_MS,
  textable,
  textAllowed,
  TEXTS_PER_KITTEN,
  unlinkParent,
  type ConsentRecord,
} from "./rules";

const H = 60 * 60_000;
const NOW = Date.UTC(2026, 10, 5, 18); // 10:00 in Los Angeles (PST)
const LA = "America/Los_Angeles";

const fresh = (): ConsentRecord => newRecord("k_x", "p_kid", "p_mom", null);

function consented(): ConsentRecord {
  const t = text(fresh(), "p_mom", "+15551234567", NOW);
  if (!("ok" in t)) throw new Error("text failed");
  return confirm(t.ok, NOW + H, LA) as ConsentRecord;
}

describe("the record (decisions 4–12)", () => {
  test("a new record is pending with one parent, nothing else", () => {
    expect(fresh()).toEqual({
      kid: "k_x",
      kitten: "p_kid",
      parents: ["p_mom"],
      state: "pending",
      phone: null,
      textedBy: null,
      textedAt: null,
      consentedBy: null,
      consentedAt: null,
      secondAt: null,
      secondSent: false,
      approved: [],
      apple: null,
      transaction: null,
    });
    expect(newRecord("k_x", "p_kid", "p_mom", "tx1").transaction).toBe("tx1");
    expect(parentState(fresh())).toBe("pending");
  });

  test("link adds a second parent once, and a transaction id when given", () => {
    const two = link(fresh(), "p_dad", null);
    expect(two.parents).toEqual(["p_mom", "p_dad"]);
    expect(link(two, "p_dad", null).parents).toEqual(["p_mom", "p_dad"]);
    expect(link(two, "p_dad", "tx9").transaction).toBe("tx9");
    expect(link({ ...two, transaction: "tx1" }, "p_mom", null).transaction).toBe("tx1");
  });

  test("text: only a linked parent, not while consented; a new number replaces the old", () => {
    expect(text(fresh(), "p_stranger", "+15551234567", NOW)).toEqual({ error: "not_parent" });
    const t = text(fresh(), "p_mom", "+15551234567", NOW);
    expect(t).toEqual({ ok: expect.objectContaining({ state: "texted", phone: "+15551234567", textedBy: "p_mom", textedAt: NOW }) });
    const again = text((t as { ok: ConsentRecord }).ok, "p_mom", "+15557654321", NOW + 5);
    expect(again).toEqual({ ok: expect.objectContaining({ phone: "+15557654321", textedAt: NOW + 5 }) });
    expect(parentState((again as { ok: ConsentRecord }).ok)).toBe("texted");
    expect(text(consented(), "p_mom", "+15551234567", NOW)).toEqual({ error: "consented" });
  });

  test("confirm: only from texted; schedules text 2", () => {
    expect(confirm(fresh(), NOW, LA)).toBeNull();
    const c = consented();
    expect(c).toMatchObject({ state: "consented", consentedBy: "p_mom", consentedAt: NOW + H, secondSent: false });
    expect(c.secondAt).toBe(secondTextAt(NOW + H, LA));
    expect(parentState(c)).toBe("on");
    expect(confirm(c, NOW, LA)).toBeNull();
  });

  test("the plus: marked sent once", () => {
    const c = secondSent(consented());
    expect(c.secondSent).toBe(true);
    expect(nextWake(c)).toBeNull();
  });

  test("texted expiry after 7 days: the phone goes, back to pending", () => {
    const t = (text(fresh(), "p_mom", "+15551234567", NOW) as { ok: ConsentRecord }).ok;
    expect(nextWake(t)).toBe(NOW + TEXTED_MS);
    expect(expireText(t, NOW + TEXTED_MS - 1)).toBe(t);
    const gone = expireText(t, NOW + TEXTED_MS);
    expect(gone).toMatchObject({ state: "pending", phone: null, textedBy: null, textedAt: null });
    expect(expireText(fresh(), NOW + TEXTED_MS * 2)).toEqual(fresh());
  });

  test("nextWake: text 2 while it's owed, nothing when pending", () => {
    expect(nextWake(fresh())).toBeNull();
    const c = consented();
    expect(nextWake(c)).toBe(c.secondAt);
  });

  test("revoke: back to pending; parents and approvals stay; phone and schedule go", () => {
    const c = setParentApprovals(link(consented(), "p_dad", null), "p_mom", ["p_mia"], ["p_mia"]) as ConsentRecord;
    const r = revoke(c);
    expect(r).toMatchObject({
      state: "pending",
      phone: null,
      textedBy: null,
      textedAt: null,
      consentedBy: null,
      consentedAt: null,
      secondAt: null,
      secondSent: false,
      parents: ["p_mom", "p_dad"],
      approved: ["p_mia"],
    });
  });

  test("unlink: the last parent deletes the record; the consenting parent leaving revokes", () => {
    expect(unlinkParent(fresh(), "p_mom")).toBeNull();
    expect(unlinkParent(fresh(), "p_other")).toEqual(fresh());
    const both = link(consented(), "p_dad", null);
    expect(unlinkParent(both, "p_dad")).toMatchObject({ state: "consented", parents: ["p_mom"] });
    expect(unlinkParent(both, "p_mom")).toMatchObject({ state: "pending", parents: ["p_dad"], phone: null });
    const texted = link((text(fresh(), "p_mom", "+15551234567", NOW) as { ok: ConsentRecord }).ok, "p_dad", null);
    expect(unlinkParent(texted, "p_mom")).toMatchObject({ state: "pending", phone: null });
    expect(unlinkParent(texted, "p_dad")).toMatchObject({ state: "texted" });
  });

  test("repoint: a merged parent becomes the other, once", () => {
    const c = consented();
    expect(repointParent(c, "p_mom", "p_acct")).toMatchObject({ parents: ["p_acct"], consentedBy: "p_acct", textedBy: "p_acct" });
    const two = link(fresh(), "p_acct", null);
    expect(repointParent(two, "p_mom", "p_acct").parents).toEqual(["p_acct"]);
    expect(repointParent(fresh(), "p_x", "p_y")).toEqual(fresh());
  });
});

describe("approvals (decisions 3, 21, 23)", () => {
  test("a parent's list is cut to the kitten's partners; strangers can't set it", () => {
    expect(setParentApprovals(fresh(), "p_stranger", ["p_mia"], ["p_mia"])).toEqual({ error: "not_parent" });
    const r = setParentApprovals(fresh(), "p_mom", ["p_mia", "p_evil", "p_mia"], ["p_mia", "p_leo"]) as ConsentRecord;
    expect(r.approved).toEqual(["p_mia"]);
  });

  test("in Apple mode the parent's list is refused, and Apple's is the one used", () => {
    const apple = setAppleApprovals(fresh(), ["p_leo", "p_evil"], ["p_mia", "p_leo"]);
    expect(apple.apple).toEqual(["p_leo"]);
    expect(setParentApprovals(apple, "p_mom", ["p_mia"], ["p_mia"])).toEqual({ error: "apple_managed" });
    expect([...approvedSet(apple)].sort()).toEqual(["p_leo", "p_mom"]);
    const back = setAppleApprovals(apple, null, ["p_mia"]);
    expect(back.apple).toBeNull();
    expect([...approvedSet(back)]).toEqual(["p_mom"]);
  });

  test("linked parents are always approved", () => {
    const r = link(setParentApprovals(fresh(), "p_mom", ["p_mia"], ["p_mia"]) as ConsentRecord, "p_dad", null);
    expect([...approvedSet(r)].sort()).toEqual(["p_dad", "p_mia", "p_mom"]);
  });
});

describe("allows: the push gate (decision 16)", () => {
  const on = () => setParentApprovals(consented(), "p_mom", ["p_mia"], ["p_mia", "p_leo"]) as ConsentRecord;

  test("nothing without a record or before consent", () => {
    expect(allows(null, "your_move", [])).toBe(false);
    expect(allows(fresh(), "pounce", ["p_mom"])).toBe(false);
    expect(allows((text(fresh(), "p_mom", "+15551234567", NOW) as { ok: ConsentRecord }).ok, "dismiss", [])).toBe(false);
  });

  test("your move: every other human approved; a seat without a player blocks", () => {
    expect(allows(on(), "your_move", ["p_mia"])).toBe(true);
    expect(allows(on(), "your_move", ["p_mia", "p_mom"])).toBe(true);
    expect(allows(on(), "your_move", ["p_mia", "p_leo"])).toBe(false);
    expect(allows(on(), "your_move", ["p_mia", null])).toBe(false);
    // Only bots: nobody else to approve.
    expect(allows(on(), "your_move", [])).toBe(true);
  });

  test("pounce: from an approved sender only", () => {
    expect(allows(on(), "pounce", ["p_mia"])).toBe(true);
    expect(allows(on(), "pounce", ["p_mom"])).toBe(true);
    expect(allows(on(), "pounce", ["p_leo"])).toBe(false);
    expect(allows(on(), "pounce", [])).toBe(false);
  });

  test("dismiss goes; every other kind stays off", () => {
    expect(allows(on(), "dismiss", [])).toBe(true);
    for (const kind of ["milestone", "reminder", "play_again", "pounce_answered", "nap", "widget", "live"]) {
      expect(allows(on(), kind, ["p_mia"])).toBe(false);
    }
  });
});

describe("secondTextAt (decision 8)", () => {
  const local = (t: number, zone: string) =>
    new Intl.DateTimeFormat("en-US", { timeZone: zone, hour: "numeric", minute: "numeric", hourCycle: "h23" }).format(new Date(t));

  test("a day later when that's daytime there", () => {
    expect(secondTextAt(NOW, LA)).toBe(NOW + 24 * H);
    const late = Date.UTC(2026, 10, 6, 3, 59); // 19:59 LA
    expect(secondTextAt(late, LA)).toBe(late + 24 * H);
  });

  test("moved to the next 10:00 when it would land at night, always within 24–48 h", () => {
    const evening = Date.UTC(2026, 10, 6, 4); // 20:00 LA
    const at = secondTextAt(evening, LA);
    expect(local(at, LA)).toBe("10:00");
    expect(at - evening).toBe(38 * H);
    const early = Date.UTC(2026, 10, 5, 14, 30); // 06:30 LA
    expect(local(secondTextAt(early, LA), LA)).toBe("10:00");
    expect(secondTextAt(early, LA) - early).toBe(27.5 * H);
    for (let m = 0; m < 24 * 60; m += 37) {
      const t = NOW + m * 60_000;
      const d = secondTextAt(t, "Asia/Tokyo") - t;
      expect(d).toBeGreaterThanOrEqual(24 * H);
      expect(d).toBeLessThanOrEqual(48 * H);
    }
  });

  test("an unknown zone counts as UTC", () => {
    const t = Date.UTC(2026, 10, 5, 22);
    expect(secondTextAt(t, null)).toBe(Date.UTC(2026, 10, 7, 10));
    expect(secondTextAt(t, "Not/AZone")).toBe(Date.UTC(2026, 10, 7, 10));
  });
});

describe("phones, codes, ids and STOP", () => {
  test("normalizePhone: US 10 and 11 digits, E.164, junk refused", () => {
    expect(normalizePhone("(555) 123-4567")).toBe("+15551234567");
    expect(normalizePhone("1 555 123 4567")).toBe("+15551234567");
    expect(normalizePhone("+44 20 7946 0958")).toBe("+442079460958");
    expect(normalizePhone("+1.555.123.4567")).toBe("+15551234567");
    for (const bad of ["", "12345", "+12", "555-CALL-NOW", "+1234567890123456", "2 555 123 4567", 42, null, "0".repeat(40)]) {
      expect(normalizePhone(bad)).toBeNull();
    }
  });

  test("newLinkCode: six digits from the RNG, zero padded", () => {
    expect(newLinkCode(() => 0)).toBe("000000");
    expect(newLinkCode(() => 0.999_999_9)).toBe("999999");
    expect(newLinkCode(() => 0.123_456_7)).toBe("123456");
    expect(LINK_CODE.test(newLinkCode(Math.random))).toBe(true);
    expect(LINK_CODE.test("12345")).toBe(false);
  });

  test("newKid: k_ and 22 base64url characters", () => {
    const k = newKid();
    expect(KID.test(k)).toBe(true);
    expect(newKid()).not.toBe(k);
  });

  test("attemptAllowed: 5 failures in 10 minutes, then wait for the oldest to age out", () => {
    const fails = Array.from({ length: MAX_FAILS - 1 }, (_, i) => NOW - i * 1000);
    expect(attemptAllowed(fails, NOW)).toBe(true);
    const full = [...fails, NOW - 9 * 60_000];
    expect(attemptAllowed(full, NOW)).toBe(false);
    expect(attemptAllowed(full, NOW - 9 * 60_000 + FAIL_WINDOW_MS)).toBe(true);
  });

  test("isStop: Twilio's opt-out words and OptOutType", () => {
    for (const w of ["STOP", " stop ", "Stopall", "UNSUBSCRIBE", "cancel", "END", "quit", "revoke", "optout"]) expect(isStop(w, null)).toBe(true);
    expect(isStop("hello", "STOP")).toBe(true);
    expect(isStop("please stop texting", null)).toBe(false);
    expect(isStop("START", "START")).toBe(false);
    expect(isStop(null, null)).toBe(false);
  });
});

describe("text limits and numbers (review I2)", () => {
  test("three texts a day per kitten; the oldest ages out", () => {
    const times = [NOW - 23 * H, NOW - H, NOW - 60_000];
    expect(textAllowed(times.slice(1), NOW, TEXTS_PER_KITTEN)).toBe(true);
    expect(textAllowed(times, NOW, TEXTS_PER_KITTEN)).toBe(false);
    expect(textAllowed(times, NOW + H, TEXTS_PER_KITTEN)).toBe(true);
  });

  test("only North American numbers are texted", () => {
    // An exchange starting with 1 is not a real number.
    expect(textable("+15551234567")).toBe(false);
    expect(textable("+14155550123")).toBe(true);
    expect(textable("+442079460958")).toBe(false);
    expect(textable("+11234567890")).toBe(false);
    expect(textable("+14151234567")).toBe(false);
  });
});

describe("approvals follow a merged partner (review M9)", () => {
  test("both lists repoint, once", () => {
    const r = { ...fresh(), approved: ["p_guest", "p_acct"], apple: ["p_guest"] };
    expect(repointPartner(r, "p_guest", "p_acct")).toMatchObject({ approved: ["p_acct"], apple: ["p_acct"] });
    expect(repointPartner(fresh(), "p_guest", "p_acct").apple).toBeNull();
  });
});
