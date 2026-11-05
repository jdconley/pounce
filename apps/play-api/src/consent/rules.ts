import { base64url } from "../players/ids";
import { localMinutes } from "../streaks/clock";

/**
 * Parent consent for a kitten (consent design §2, §4; plan decisions 4–23).
 * Pure: the record, its state machine, the push filter, and the small rules
 * around it (the second text's time, phones, link codes, STOP words).
 */

export type ConsentState = "pending" | "texted" | "consented";
/** What the parent's Kittens panel shows. */
export type ParentState = "pending" | "texted" | "on";

export type ConsentRecord = {
  /** The public id the parent's app addresses this kitten by (`k_…`). */
  kid: string;
  /** The kitten's player id. */
  kitten: string;
  /** Linked signed-in adults, in link order. */
  parents: string[];
  state: ConsentState;
  /** E.164, only while texted or consented (D1: kept only while consent lasts). */
  phone: string | null;
  textedBy: string | null;
  textedAt: number | null;
  consentedBy: string | null;
  consentedAt: number | null;
  /** When the second text ("the plus") is due. */
  secondAt: number | null;
  secondSent: boolean;
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

/** A texted number nobody confirms is deleted after this long (16 CFR 312.5(c)(1)). */
export const TEXTED_MS = 7 * DAY_MS;
/** A link code lives this long, and is used once. */
export const LINK_CODE_MS = 10 * MIN_MS;
export const LINK_CODE = /^[0-9]{6}$/;
const LINK_CODE_DIGITS = 6;
/** Failed link tries a parent gets in `FAIL_WINDOW_MS`. */
export const MAX_FAILS = 5;
export const FAIL_WINDOW_MS = 10 * MIN_MS;
export const KID = /^k_[A-Za-z0-9_-]{22}$/;
const KID_BYTES = 16;

const SECOND_AFTER_MS = DAY_MS;
/** Text 2 goes out between 10:00 and 20:00 local. */
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
    textedBy: null,
    textedAt: null,
    consentedBy: null,
    consentedAt: null,
    secondAt: null,
    secondSent: false,
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

/** Texts a kitten's record may send in a day, and a parent across their kittens (review I2: no SMS pumping). */
export const TEXTS_PER_KITTEN = 3;
export const TEXTS_PER_PARENT = 5;
export const TEXT_WINDOW_MS = DAY_MS;

/** Another text may go: fewer than `max` in the last day. */
export function textAllowed(times: number[], now: number, max: number): boolean {
  return times.filter((at) => at > now - TEXT_WINDOW_MS).length < max;
}

/** The sending number is US toll-free or A2P 10DLC (D1), so only North American numbers are texted. */
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

/** A linked parent sends text 1 to `phone` (normalized already). */
export function text(r: ConsentRecord, parent: string, phone: string, now: number): { ok: ConsentRecord } | Refused<"not_parent" | "consented"> {
  if (!r.parents.includes(parent)) return { error: "not_parent" };
  if (r.state === "consented") return { error: "consented" };
  return { ok: { ...r, state: "texted", phone, textedBy: parent, textedAt: now } };
}

/** The confirm link was used. Null unless texted. */
export function confirm(r: ConsentRecord, now: number, zone: string | null): ConsentRecord | null {
  if (r.state !== "texted") return null;
  return { ...r, state: "consented", consentedBy: r.textedBy, consentedAt: now, secondAt: secondTextAt(now, zone), secondSent: false };
}

export const secondSent = (r: ConsentRecord): ConsentRecord => ({ ...r, secondSent: true });

const cleared = { phone: null, textedBy: null, textedAt: null, consentedBy: null, consentedAt: null, secondAt: null, secondSent: false };

/** Back to pending: the phone and the schedule go; parents and approvals stay (decision 9). */
export function revoke(r: ConsentRecord): ConsentRecord {
  return { ...r, state: "pending", ...cleared };
}

/** Texted but never confirmed for 7 days: the number is deleted (decision 7). */
export function expireText(r: ConsentRecord, now: number): ConsentRecord {
  if (r.state !== "texted" || (r.textedAt as number) + TEXTED_MS > now) return r;
  return revoke(r);
}

/** The next time the record's alarm has work: text 2, or the texted expiry. */
export function nextWake(r: ConsentRecord): number | null {
  if (r.state === "consented") return r.secondSent ? null : r.secondAt;
  if (r.state === "texted") return (r.textedAt as number) + TEXTED_MS;
  return null;
}

/** A parent leaves. Null: nobody is left, so the record goes. The parent behind the consent (or the text) leaving revokes it. */
export function unlinkParent(r: ConsentRecord, parent: string): ConsentRecord | null {
  if (!r.parents.includes(parent)) return r;
  const parents = r.parents.filter((p) => p !== parent);
  if (parents.length === 0) return null;
  const theirs = r.state === "consented" ? r.consentedBy === parent : r.state === "texted" && r.textedBy === parent;
  return theirs ? { ...revoke(r), parents } : { ...r, parents };
}

/** After a merge: parent `from` is now `to`. */
export function repointParent(r: ConsentRecord, from: string, to: string): ConsentRecord {
  if (!r.parents.includes(from)) return r;
  const swap = (p: string | null) => (p === from ? to : p);
  return {
    ...r,
    parents: [...new Set(r.parents.map((p) => swap(p) as string))],
    textedBy: swap(r.textedBy),
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

/**
 * The push gate (decision 16). `senders` are the people behind the push:
 * the other human seats for "your move" (null for a seat with no player),
 * the sender for a pounce.
 */
export function allows(r: ConsentRecord | null, kind: string, senders: (string | null)[]): boolean {
  if (!r || r.state !== "consented") return false;
  if (kind === "dismiss") return true;
  if (kind !== "your_move" && kind !== "pounce") return false;
  if (kind === "pounce" && senders.length === 0) return false;
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

/** A day after consent, moved to the next 10:00 when that falls outside 10:00–20:00 local: within 24–48 h. */
export function secondTextAt(consentedAt: number, zone: string | null): number {
  const t = consentedAt + SECOND_AFTER_MS;
  const m = minutesIn(t, zone);
  if (m >= DAY_START_MIN && m < DAY_END_MIN) return t;
  const wait = m < DAY_START_MIN ? DAY_START_MIN - m : DAY_MIN - m + DAY_START_MIN;
  return t + wait * MIN_MS;
}

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

/** Twilio's standard opt-out words (Advanced Opt-Out), or its `OptOutType`. */
const STOP_WORDS = ["STOP", "STOPALL", "UNSUBSCRIBE", "CANCEL", "END", "QUIT", "REVOKE", "OPTOUT"];

export function isStop(body: string | null, optOutType: string | null): boolean {
  if (optOutType?.toUpperCase() === "STOP") return true;
  return STOP_WORDS.includes((body ?? "").trim().toUpperCase());
}
