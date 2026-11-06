import { describe, expect, test } from "vitest";

import {
  allows,
  attemptAllowed,
  CODE_MS,
  confirm,
  expireCode,
  FAIL_WINDOW_MS,
  intoWindow,
  isOldShape,
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
  PLUS_GIVE_UP_MS,
  plusDone,
  plusRetryAt,
  plusTimeAt,
  repointParent,
  repointPartner,
  resend,
  RESEND_MS,
  revoke,
  setAppleApprovals,
  setParentApprovals,
  startCode,
  textable,
  textAllowed,
  TEXTS_PER_KITTEN,
  unlinkParent,
  upgrade,
  VERIFY_CODE,
  type ConsentRecord,
} from "./rules";

const H = 60 * 60_000;
const NOW = Date.UTC(2026, 10, 5, 18); // 10:00 in Los Angeles (PST)
const LA = "America/Los_Angeles";

const fresh = (): ConsentRecord => newRecord("k_x", "p_kid", "p_mom", null);

const waiting = (): ConsentRecord => (startCode(fresh(), "p_mom", "+15551234567", NOW) as { ok: ConsentRecord }).ok;

function consented(): ConsentRecord {
  const t = startCode(fresh(), "p_mom", "+15551234567", NOW);
  if (!("ok" in t)) throw new Error("start failed");
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
      codeBy: null,
      codeAt: null,
      consentedBy: null,
      consentedAt: null,
      plusAt: null,
      plusSent: false,
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

  test("startCode: only a linked parent, not while consented; a new number replaces the old", () => {
    expect(startCode(fresh(), "p_stranger", "+15551234567", NOW)).toEqual({ error: "not_parent" });
    const t = startCode(fresh(), "p_mom", "+15551234567", NOW);
    expect(t).toEqual({ ok: expect.objectContaining({ state: "code", phone: "+15551234567", codeBy: "p_mom", codeAt: NOW }) });
    const again = startCode((t as { ok: ConsentRecord }).ok, "p_mom", "+15557654321", NOW + 5);
    expect(again).toEqual({ ok: expect.objectContaining({ phone: "+15557654321", codeAt: NOW + 5 }) });
    expect(parentState((again as { ok: ConsentRecord }).ok)).toBe("code");
    expect(startCode(consented(), "p_mom", "+15551234567", NOW)).toEqual({ error: "consented" });
  });

  test("resend: only while waiting for the code, by a linked parent, and not within 30 s", () => {
    expect(resend(fresh(), "p_mom", NOW)).toEqual({ error: "not_waiting" });
    expect(resend(consented(), "p_mom", NOW)).toEqual({ error: "not_waiting" });
    expect(resend(waiting(), "p_stranger", NOW + RESEND_MS)).toEqual({ error: "not_parent" });
    expect(resend(waiting(), "p_mom", NOW + RESEND_MS - 1)).toEqual({ error: "too_soon" });
    const dad = link(waiting(), "p_dad", null);
    expect(resend(dad, "p_dad", NOW + RESEND_MS)).toEqual({ ok: expect.objectContaining({ codeAt: NOW + RESEND_MS, codeBy: "p_mom", phone: "+15551234567" }) });
  });

  test("confirm: only while waiting for the code; schedules the plus", () => {
    expect(confirm(fresh(), NOW, LA)).toBeNull();
    const c = consented();
    expect(c).toMatchObject({ state: "consented", consentedBy: "p_mom", consentedAt: NOW + H, plusSent: false });
    expect(c.plusAt).toBe(plusTimeAt(NOW + H, LA));
    expect(parentState(c)).toBe("on");
    expect(confirm(c, NOW, LA)).toBeNull();
  });

  test("the plus: marked done once", () => {
    const c = plusDone(consented());
    expect(c.plusSent).toBe(true);
    expect(nextWake(c)).toBeNull();
  });

  test("the code state ends after 30 minutes without consent: the phone goes, back to pending", () => {
    const t = waiting();
    expect(nextWake(t)).toBe(NOW + CODE_MS);
    expect(expireCode(t, NOW + CODE_MS - 1)).toBe(t);
    const gone = expireCode(t, NOW + CODE_MS);
    expect(gone).toMatchObject({ state: "pending", phone: null, codeBy: null, codeAt: null });
    expect(expireCode(fresh(), NOW + CODE_MS * 2)).toEqual(fresh());
  });

  test("nextWake: text 2 while it's owed, nothing when pending", () => {
    expect(nextWake(fresh())).toBeNull();
    const c = consented();
    expect(nextWake(c)).toBe(c.plusAt);
  });

  test("revoke: back to pending; parents and approvals stay; phone and schedule go", () => {
    const c = setParentApprovals(link(consented(), "p_dad", null), "p_mom", ["p_mia"], ["p_mia"]) as ConsentRecord;
    const r = revoke(c);
    expect(r).toMatchObject({
      state: "pending",
      phone: null,
      codeBy: null,
      codeAt: null,
      consentedBy: null,
      consentedAt: null,
      plusAt: null,
      plusSent: false,
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
    const code = link(waiting(), "p_dad", null);
    expect(unlinkParent(code, "p_mom")).toMatchObject({ state: "pending", phone: null });
    expect(unlinkParent(code, "p_dad")).toMatchObject({ state: "code" });
  });

  test("repoint: a merged parent becomes the other, once", () => {
    const c = consented();
    expect(repointParent(c, "p_mom", "p_acct")).toMatchObject({ parents: ["p_acct"], consentedBy: "p_acct", codeBy: "p_acct" });
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
    expect(allows(waiting(), "dismiss", [])).toBe(false);
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

describe("the plus: its time and retries inside 10:00–20:00 (decision 8, Verify)", () => {
  const local = (t: number, zone: string) =>
    new Intl.DateTimeFormat("en-US", { timeZone: zone, hour: "numeric", minute: "numeric", hourCycle: "h23" }).format(new Date(t));

  test("a day later when that's daytime there", () => {
    expect(plusTimeAt(NOW, LA)).toBe(NOW + 24 * H);
    const late = Date.UTC(2026, 10, 6, 3, 59); // 19:59 LA
    expect(plusTimeAt(late, LA)).toBe(late + 24 * H);
  });

  test("moved to the next 10:00 when it would land at night, always within 24–48 h", () => {
    const evening = Date.UTC(2026, 10, 6, 4); // 20:00 LA
    const at = plusTimeAt(evening, LA);
    expect(local(at, LA)).toBe("10:00");
    expect(at - evening).toBe(38 * H);
    const early = Date.UTC(2026, 10, 5, 14, 30); // 06:30 LA
    expect(local(plusTimeAt(early, LA), LA)).toBe("10:00");
    expect(plusTimeAt(early, LA) - early).toBe(27.5 * H);
    for (let m = 0; m < 24 * 60; m += 37) {
      const t = NOW + m * 60_000;
      const d = plusTimeAt(t, "Asia/Tokyo") - t;
      expect(d).toBeGreaterThanOrEqual(24 * H);
      expect(d).toBeLessThanOrEqual(48 * H);
    }
  });

  test("intoWindow: daytime stays, night moves to the next 10:00", () => {
    expect(intoWindow(NOW, LA)).toBe(NOW);
    const evening = Date.UTC(2026, 10, 6, 4); // 20:00 LA
    expect(local(intoWindow(evening, LA), LA)).toBe("10:00");
    expect(intoWindow(evening, LA) - evening).toBe(14 * H);
  });

  test("intoWindow lands at 10:00 local across a DST change (review M11)", () => {
    const beforeFallBack = Date.UTC(2026, 10, 1, 5); // 22:00 PDT, 31 October
    expect(local(intoWindow(beforeFallBack, LA), LA)).toBe("10:00");
    const beforeSpring = Date.UTC(2027, 2, 14, 6); // 22:00 PST, 13 March
    expect(local(intoWindow(beforeSpring, LA), LA)).toBe("10:00");
  });

  test("a failed push is retried an hour later, never outside the window; a day of failures gives up", () => {
    const c = consented();
    expect(plusRetryAt(NOW, LA)).toBe(NOW + H);
    const late = Date.UTC(2026, 10, 6, 3, 30); // 19:30 LA: an hour later is 20:30
    expect(local(plusRetryAt(late, LA), LA)).toBe("10:00");
    expect(PLUS_GIVE_UP_MS).toBe(24 * H);
    expect((c.plusAt as number) + PLUS_GIVE_UP_MS).toBeGreaterThan(c.plusAt as number);
  });

  test("an unknown zone counts as UTC", () => {
    const t = Date.UTC(2026, 10, 5, 22);
    expect(plusTimeAt(t, null)).toBe(Date.UTC(2026, 10, 7, 10));
    expect(plusTimeAt(t, "Not/AZone")).toBe(Date.UTC(2026, 10, 7, 10));
  });
});

describe("phones, codes and ids", () => {
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

  test("the Verify code is six digits", () => {
    expect(VERIFY_CODE.test("012345")).toBe(true);
    for (const bad of ["12345", "1234567", "12a456", " 12345"]) expect(VERIFY_CODE.test(bad)).toBe(false);
  });
});

describe("code limits and numbers (review I2)", () => {
  test("three codes a day per kitten; the oldest ages out", () => {
    const times = [NOW - 23 * H, NOW - H, NOW - 60_000];
    expect(textAllowed(times.slice(1), NOW, TEXTS_PER_KITTEN)).toBe(true);
    expect(textAllowed(times, NOW, TEXTS_PER_KITTEN)).toBe(false);
    expect(textAllowed(times, NOW + H, TEXTS_PER_KITTEN)).toBe(true);
  });

  test("only North American numbers get a code", () => {
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

describe("stored records from the text plus build", () => {
  test("a record without the Verify fields is upgraded and revoked: its texted channels are gone (review I3)", () => {
    const old = {
      kid: "k_x",
      kitten: "p_kid",
      parents: ["p_mom"],
      state: "texted" as const,
      phone: "+14155550123",
      textedBy: "p_mom",
      textedAt: NOW,
      consentedBy: null,
      consentedAt: null,
      secondAt: null,
      secondSent: false,
      approved: ["p_mia"],
      apple: null,
      transaction: "tx1",
    };
    expect(upgrade(old)).toEqual({ ...fresh(), approved: ["p_mia"], transaction: "tx1" });
    const on = { ...old, state: "consented" as const, consentedBy: "p_mom", consentedAt: NOW, secondAt: NOW + 24 * H, secondSent: true };
    // Consent given by text plus promised a revoke link and STOP, which Verify removed: it ends.
    expect(upgrade(on)).toEqual({ ...fresh(), approved: ["p_mia"], transaction: "tx1" });
    expect(upgrade(on)).not.toHaveProperty("textedBy");
    expect(isOldShape(on)).toBe(true);
    expect(isOldShape(consented())).toBe(false);
    const pending = { ...old, state: "pending" as const, phone: null, textedBy: null, textedAt: null };
    expect(upgrade(pending)).toEqual({ ...fresh(), approved: ["p_mia"], transaction: "tx1" });
    // Fields an older write left out read as unset.
    const sparse: Record<string, unknown> = { ...on, textedBy: undefined };
    for (const k of ["textedAt", "secondAt", "secondSent"]) delete sparse[k];
    expect(upgrade(sparse as never)).toMatchObject({ state: "pending", codeBy: null, codeAt: null, plusAt: null, plusSent: false });
  });

  test("a current record is left as it is", () => {
    const c = consented();
    expect(upgrade(c)).toBe(c);
  });
});
