import { base64url } from "../players/ids";
import { localMinutes } from "../streaks/clock";

/**
 * Parent consent for a kitten (consent design §2, §4 D1 and D6; plan
 * decisions 4–23, 46–55). Pure: the record, its state machine, the push
 * filter, and the small rules around it (the confirmation push's time,
 * phones, link codes, code limits).
 */

/** `code`: Twilio Verify texted the parent a code, which they haven't entered yet. */
export type ConsentState = "pending" | "code" | "consented";
/** What the parent's Kittens panel shows. */
export type ParentState = "pending" | "code" | "on";

export type ConsentRecord = {
  /** The public id the parent's app addresses this kitten by (`k_…`). */
  kid: string;
  /** The kitten's player id. */
  kitten: string;
  /** Linked signed-in adults, in link order. */
  parents: string[];
  state: ConsentState;
  /** E.164, only while waiting for the code or consented (D1: kept only while consent lasts). */
  phone: string | null;
  /** The parent who entered the number, and when the last code went. */
  codeBy: string | null;
  codeAt: number | null;
  consentedBy: string | null;
  consentedAt: number | null;
  /** When the confirmation push to the consenting parent's devices ("the plus", D6) is due. */
  plusAt: number | null;
  /** Some device of theirs accepted it: the Kittens panel shows consent as confirmed. */
  plusSent: boolean;
  /** The parent's own list: partner player ids. */
  approved: string[];
  /** Apple's list (Communication Limits), mirrored from the kitten's device; null in parent mode. */
  apple: string[] | null;
  /** `AppTransaction.appTransactionID`, for `RESCIND_CONSENT`. */
  transaction: string | null;
};

const MIN_MS = 60_000;
const HOUR_MS = 60 * MIN_MS;
const DAY_MS = 24 * HOUR_MS;

/**
 * A number whose code nobody enters is deleted after this long (16 CFR
 * 312.5(c)(1)). Verify's own code lasts 10 minutes; the extra time lets the
 * parent ask for a fresh one without typing the number again.
 */
export const CODE_MS = 30 * MIN_MS;
/** The code Verify texts: six digits (the Verify Service's code length). */
export const VERIFY_CODE = /^[0-9]{6}$/;
/** Another code for the same number waits this long, so a double tap doesn't spend the day's sends. */
export const RESEND_MS = 30_000;
/** A link code lives this long, and is used once. */
export const LINK_CODE_MS = 10 * MIN_MS;
export const LINK_CODE = /^[0-9]{6}$/;
const LINK_CODE_DIGITS = 6;
/** Failed link tries a parent gets in `FAIL_WINDOW_MS`. */
export const MAX_FAILS = 5;
export const FAIL_WINDOW_MS = 10 * MIN_MS;
export const KID = /^k_[A-Za-z0-9_-]{22}$/;
const KID_BYTES = 16;

const PLUS_AFTER_MS = DAY_MS;
const PLUS_RETRY_MS = HOUR_MS;
/** A confirmation push no device accepted for this long ends consent: no plus, no consent (review I4). */
export const PLUS_GIVE_UP_MS = DAY_MS;
/** The confirmation push goes out between 10:00 and 20:00 local. */
const DAY_START_MIN = 10 * 60;
const DAY_END_MIN = 20 * 60;
const DAY_MIN = 24 * 60;

export function newRecord(kid: string, kitten: string, parent: string, transaction: string | null): ConsentRecord {
  return {
    kid,
    kitten,
    parents: [parent],
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
    transaction,
  };
}

export const newKid = (): string => `k_${base64url(crypto.getRandomValues(new Uint8Array(KID_BYTES)))}`;

/** Six digits, uniform over the RNG's [0, 1). */
export function newLinkCode(rng: () => number): string {
  return String(Math.floor(rng() * 10 ** LINK_CODE_DIGITS)).padStart(LINK_CODE_DIGITS, "0");
}

/**
 * Codes a kitten's record may send in a day, a parent across their kittens,
 * and one number (by its HMAC) from anyone (review I2: no SMS pumping, and no
 * texting someone else's phone over and over). Resends count.
 */
export const TEXTS_PER_KITTEN = 3;
export const TEXTS_PER_PARENT = 5;
export const TEXTS_PER_PHONE = 3;
export const TEXT_WINDOW_MS = DAY_MS;

/** Another text may go: fewer than `max` in the last day. */
export function textAllowed(times: number[], now: number, max: number): boolean {
  return times.filter((at) => at > now - TEXT_WINDOW_MS).length < max;
}

/** Only North American numbers get a code (D1): it closes SMS pumping abroad, and Verify's geo permissions match. */
export const textable = (e164: string): boolean => /^\+1[2-9][0-9]{2}[2-9][0-9]{6}$/.test(e164);

/** A parent may try another code: fewer than `MAX_FAILS` failures in the last 10 minutes. */
export function attemptAllowed(fails: number[], now: number): boolean {
  return fails.filter((at) => at > now - FAIL_WINDOW_MS).length < MAX_FAILS;
}

export function link(r: ConsentRecord, parent: string, transaction: string | null): ConsentRecord {
  return {
    ...r,
    parents: r.parents.includes(parent) ? r.parents : [...r.parents, parent],
    transaction: transaction ?? r.transaction,
  };
}

export type Refused<E extends string> = { error: E };

/** A linked parent asks for a code at `phone` (normalized already). A new number replaces the old. */
export function startCode(r: ConsentRecord, parent: string, phone: string, now: number): { ok: ConsentRecord } | Refused<"not_parent" | "consented"> {
  if (!r.parents.includes(parent)) return { error: "not_parent" };
  if (r.state === "consented") return { error: "consented" };
  return { ok: { ...r, state: "code", phone, codeBy: parent, codeAt: now } };
}

/** Another code to the same number, by any linked parent. */
export function resend(r: ConsentRecord, parent: string, now: number): { ok: ConsentRecord } | Refused<"not_parent" | "not_waiting" | "too_soon"> {
  if (r.state !== "code") return { error: "not_waiting" };
  if (!r.parents.includes(parent)) return { error: "not_parent" };
  if ((r.codeAt as number) + RESEND_MS > now) return { error: "too_soon" };
  return { ok: { ...r, codeAt: now } };
}

/** Verify approved the code. Null unless waiting for one. The number's owner is the consenting parent. */
export function confirm(r: ConsentRecord, now: number, zone: string | null): ConsentRecord | null {
  if (r.state !== "code") return null;
  return { ...r, state: "consented", consentedBy: r.codeBy, consentedAt: now, plusAt: plusTimeAt(now, zone), plusSent: false };
}

export const plusDone = (r: ConsentRecord): ConsentRecord => ({ ...r, plusSent: true });

const cleared = { phone: null, codeBy: null, codeAt: null, consentedBy: null, consentedAt: null, plusAt: null, plusSent: false };

/** Back to pending: the phone and the schedule go; parents and approvals stay (decision 9). */
export function revoke(r: ConsentRecord): ConsentRecord {
  return { ...r, state: "pending", ...cleared };
}

/** Waiting for a code for 30 minutes: the number is deleted (decision 7). */
export function expireCode(r: ConsentRecord, now: number): ConsentRecord {
  if (r.state !== "code" || (r.codeAt as number) + CODE_MS > now) return r;
  return revoke(r);
}

/** The next time the record's alarm has work: the confirmation push, or the code's expiry. */
export function nextWake(r: ConsentRecord): number | null {
  if (r.state === "consented") return r.plusSent ? null : r.plusAt;
  if (r.state === "code") return (r.codeAt as number) + CODE_MS;
  return null;
}

/** A parent leaves. Null: nobody is left, so the record goes. The parent behind the consent (or the number) leaving revokes it. */
export function unlinkParent(r: ConsentRecord, parent: string): ConsentRecord | null {
  if (!r.parents.includes(parent)) return r;
  const parents = r.parents.filter((p) => p !== parent);
  if (parents.length === 0) return null;
  const theirs = r.state === "consented" ? r.consentedBy === parent : r.state === "code" && r.codeBy === parent;
  return theirs ? { ...revoke(r), parents } : { ...r, parents };
}

/** After a merge: parent `from` is now `to`. */
export function repointParent(r: ConsentRecord, from: string, to: string): ConsentRecord {
  if (!r.parents.includes(from)) return r;
  const swap = (p: string | null) => (p === from ? to : p);
  return {
    ...r,
    parents: [...new Set(r.parents.map((p) => swap(p) as string))],
    codeBy: swap(r.codeBy),
    consentedBy: swap(r.consentedBy),
  };
}

/** After a merge: approved partner `from` is now `to` (review M9), in both lists. */
export function repointPartner(r: ConsentRecord, from: string, to: string): ConsentRecord {
  const swap = (list: string[]) => [...new Set(list.map((p) => (p === from ? to : p)))];
  return { ...r, approved: swap(r.approved), apple: r.apple === null ? null : swap(r.apple) };
}

const within = (list: string[], partners: string[]) => [...new Set(list.filter((p) => partners.includes(p)))];

/** The parent's toggles, cut to the kitten's real partners (decision 23). Refused in Apple mode. */
export function setParentApprovals(
  r: ConsentRecord,
  parent: string,
  approved: string[],
  partners: string[],
): ConsentRecord | Refused<"not_parent" | "apple_managed"> {
  if (!r.parents.includes(parent)) return { error: "not_parent" };
  if (r.apple !== null) return { error: "apple_managed" };
  return { ...r, approved: within(approved, partners) };
}

/** Apple's answers from the kitten's device, or null when Communication Limits are off (decision 21). */
export function setAppleApprovals(r: ConsentRecord, apple: string[] | null, partners: string[]): ConsentRecord {
  return { ...r, apple: apple === null ? null : within(apple, partners) };
}

/** Who may reach the kitten: Apple's list or the parent's, plus every linked parent (decision 3). */
export function approvedSet(r: ConsentRecord): Set<string> {
  return new Set([...(r.apple ?? r.approved), ...r.parents]);
}

/** Pushes one person sends: they need a sender, and that sender approved. */
const FROM_ONE: readonly string[] = ["pounce", "nudge"];

/**
 * The push gate (decision 16). `senders` are the people behind the push:
 * the other human seats for "your move" (null for a seat with no player),
 * the sender for a pounce or a nudge (a nudge asks for the move "your move"
 * already allows, from one person, so it passes like a pounce).
 */
export function allows(r: ConsentRecord | null, kind: string, senders: (string | null)[]): boolean {
  if (!r || r.state !== "consented") return false;
  if (kind === "dismiss") return true;
  if (kind !== "your_move" && !FROM_ONE.includes(kind)) return false;
  if (FROM_ONE.includes(kind) && senders.length === 0) return false;
  const ok = approvedSet(r);
  return senders.every((s) => s !== null && ok.has(s));
}

export function parentState(r: ConsentRecord): ParentState {
  return r.state === "consented" ? "on" : r.state;
}

function minutesIn(t: number, zone: string | null): number {
  try {
    return localMinutes(t, zone ?? "UTC");
  } catch {
    return localMinutes(t, "UTC");
  }
}

/** `t`, or the next 10:00 local when `t` falls outside 10:00–20:00 there. */
export function intoWindow(t: number, zone: string | null): number {
  const m = minutesIn(t, zone);
  if (m >= DAY_START_MIN && m < DAY_END_MIN) return t;
  const wait = m < DAY_START_MIN ? DAY_START_MIN - m : DAY_MIN - m + DAY_START_MIN;
  const at = t + wait * MIN_MS;
  // Across a DST change the clock moved by an hour on the way: land on 10:00 itself (review M11).
  return at + (DAY_START_MIN - minutesIn(at, zone)) * MIN_MS;
}

/** A day after consent, moved into 10:00–20:00 local: within 24–48 h. */
export const plusTimeAt = (consentedAt: number, zone: string | null): number => intoWindow(consentedAt + PLUS_AFTER_MS, zone);

/** A push no device accepted is tried again an hour later, still inside the window. */
export const plusRetryAt = (now: number, zone: string | null): number => intoWindow(now + PLUS_RETRY_MS, zone);

const PHONE_CHARS = /^[0-9+().\s-]+$/;
const E164_MIN_DIGITS = 8;
const E164_MAX_DIGITS = 15;
const US_DIGITS = 10;

/** E.164 from what a parent typed: `+` and 8–15 digits, or a US number of 10 digits (or 11 with the 1). */
export function normalizePhone(raw: unknown): string | null {
  if (typeof raw !== "string" || raw.length > 32 || !PHONE_CHARS.test(raw)) return null;
  const plus = raw.trim().startsWith("+");
  const digits = raw.replace(/[^0-9]/g, "");
  if (plus) return digits.length >= E164_MIN_DIGITS && digits.length <= E164_MAX_DIGITS ? `+${digits}` : null;
  if (digits.length === US_DIGITS) return `+1${digits}`;
  if (digits.length === US_DIGITS + 1 && digits.startsWith("1")) return `+${digits}`;
  return null;
}

type Stored = Omit<ConsentRecord, "state" | "codeBy" | "codeAt" | "plusAt" | "plusSent"> & {
  state: ConsentState | "texted";
  textedBy?: string | null;
  textedAt?: number | null;
  secondAt?: number | null;
  secondSent?: boolean;
};

/** Stored by the text plus build, before Verify. */
export const isOldShape = (stored: ConsentRecord | Stored): stored is Stored => "textedBy" in stored;

/**
 * A record stored by the text plus build (before Verify) in today's shape,
 * and revoked (review I3): a text's confirm link no longer works, and a
 * consent given by text plus was promised a revoke link and STOP, which went
 * with Verify. The number goes; parents and approvals stay, so the parent can
 * consent again with a code.
 */
export function upgrade(stored: ConsentRecord | Stored): ConsentRecord {
  if (!isOldShape(stored)) return stored;
  const { textedBy, textedAt, secondAt, secondSent, ...rest } = stored;
  return revoke({ ...rest, codeBy: textedBy ?? null, codeAt: textedAt ?? null, plusAt: secondAt ?? null, plusSent: secondSent ?? false } as ConsentRecord);
}
