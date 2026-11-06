/**
 * Twilio Verify for parent consent (consent design D1 and its Verify change,
 * D6; plan decisions 46–49): starting a verification texts the parent a
 * six-digit code from Twilio's own pre-registered senders, and checking it
 * says whether the parent typed the right one. Basic auth with an API key.
 * Optional like the APNs key: without all four secrets nothing is sent.
 *
 * Verify sends only its own code message ("Your Pounce verification code
 * is: …"), so no link or text of ours ever reaches the phone.
 */

export type TwilioEnv = {
  TWILIO_ACCOUNT_SID?: string;
  TWILIO_API_KEY_SID?: string;
  TWILIO_API_KEY_SECRET?: string;
  TWILIO_VERIFY_SERVICE_SID?: string;
};

export type TwilioConfig = {
  /** The account the API key and Verify Service belong to. Verify's URLs don't name it; it is kept so the set is whole. */
  accountSid: string;
  apiKeySid: string;
  apiKeySecret: string;
  /** The Verify Service (`VA…`). */
  serviceSid: string;
};

const API = "https://verify.twilio.com/v2/Services";

/** All four secrets, or null. */
export function twilioConfig(env: TwilioEnv): TwilioConfig | null {
  const { TWILIO_ACCOUNT_SID: a, TWILIO_API_KEY_SID: k, TWILIO_API_KEY_SECRET: s, TWILIO_VERIFY_SERVICE_SID: v } = env;
  if (!a || !k || !s || !v) return null;
  return { accountSid: a, apiKeySid: k, apiKeySecret: s, serviceSid: v };
}

/** Verify's error codes we act on (twilio.com/docs/verify/api/error-codes). */
const MAX_SEND_ATTEMPTS = 60203;
const MAX_CHECK_ATTEMPTS = 60202;
const TOO_MANY_REQUESTS = 20429;
/** Invalid parameter (the number), landline, invalid `To`, not a mobile number. */
const BAD_NUMBER = [60200, 60205, 21211, 21614];
const HTTP_TOO_MANY = 429;
const HTTP_NOT_FOUND = 404;
/** A Verify call runs inside the consent record's one-at-a-time queue, so it can't hang it (review M6). */
const TIMEOUT_MS = 10_000;

async function post(
  cfg: TwilioConfig,
  path: string,
  form: Record<string, string>,
  fetcher: typeof fetch,
  timeoutMs: number,
): Promise<{ status: number; body: unknown } | null> {
  try {
    const res = await fetcher(`${API}/${encodeURIComponent(cfg.serviceSid)}/${path}`, {
      method: "POST",
      signal: AbortSignal.timeout(timeoutMs),
      headers: {
        authorization: `Basic ${btoa(`${cfg.apiKeySid}:${cfg.apiKeySecret}`)}`,
        "content-type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams(form).toString(),
    });
    let body: unknown = null;
    try {
      body = await res.json();
    } catch {
      body = null;
    }
    return { status: res.status, body };
  } catch {
    return null;
  }
}

const field = (body: unknown, key: string): unknown => (typeof body === "object" && body !== null ? (body as Record<string, unknown>)[key] : undefined);

export type StartResult = "sent" | "limited" | "bad_number" | "failed";

/**
 * Texts a code to `to` (E.164) by SMS. Within a verification's 10 minutes
 * Verify sends the same code again, up to 5 sends. Never throws.
 */
export async function startVerification(cfg: TwilioConfig, to: string, fetcher: typeof fetch, timeoutMs = TIMEOUT_MS): Promise<StartResult> {
  const res = await post(cfg, "Verifications", { To: to, Channel: "sms" }, fetcher, timeoutMs);
  if (!res) return "failed";
  if (res.status >= 200 && res.status < 300) return "sent";
  const code = field(res.body, "code");
  if (res.status === HTTP_TOO_MANY || code === MAX_SEND_ATTEMPTS || code === TOO_MANY_REQUESTS) return "limited";
  if (typeof code === "number" && BAD_NUMBER.includes(code)) return "bad_number";
  return "failed";
}

/**
 * `approved`: the right code. `wrong`: not it, the verification lives on.
 * `expired`: Verify has no live verification for the number any more (its
 * 10 minutes passed, too many wrong tries, or already approved), so only a
 * fresh code can help. Never throws.
 */
export type CheckResult = "approved" | "wrong" | "expired" | "limited" | "failed";

export async function checkVerification(cfg: TwilioConfig, to: string, code: string, fetcher: typeof fetch, timeoutMs = TIMEOUT_MS): Promise<CheckResult> {
  const res = await post(cfg, "VerificationCheck", { To: to, Code: code }, fetcher, timeoutMs);
  if (!res) return "failed";
  if (res.status === HTTP_NOT_FOUND) return "expired";
  if (res.status === HTTP_TOO_MANY || field(res.body, "code") === MAX_CHECK_ATTEMPTS) return "limited";
  if (res.status !== 200) return "failed";
  const status = field(res.body, "status");
  if (typeof status !== "string") return "failed";
  if (status === "approved") return "approved";
  return status === "pending" ? "wrong" : "expired";
}
