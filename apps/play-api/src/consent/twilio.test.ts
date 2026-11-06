import { describe, expect, test } from "vitest";

import { checkVerification, startVerification, twilioConfig } from "./twilio";

// Fixture values, never real ones.
const CFG = { accountSid: "ACtest", apiKeySid: "SKtest", apiKeySecret: "secret-test", serviceSid: "VAtest" };
const BASE = "https://verify.twilio.com/v2/Services/VAtest";

type Fetcher = typeof fetch;
const reply = (status: number, body: unknown) =>
  (async () => new Response(typeof body === "string" ? body : JSON.stringify(body), { status })) as unknown as Fetcher;
const down = (async () => {
  throw new Error("offline");
}) as unknown as Fetcher;

/** A fetcher that keeps the request it was given. */
function recorder(status: number, body: unknown): { fetcher: Fetcher; seen: () => Request } {
  let seen: Request | null = null;
  const fetcher = (async (input: RequestInfo | URL, init?: RequestInit) => {
    seen = new Request(input, init);
    return new Response(JSON.stringify(body), { status });
  }) as Fetcher;
  return { fetcher, seen: () => seen as unknown as Request };
}

describe("twilioConfig", () => {
  test("needs all four secrets", () => {
    const all = {
      TWILIO_ACCOUNT_SID: "ACtest",
      TWILIO_API_KEY_SID: "SKtest",
      TWILIO_API_KEY_SECRET: "secret-test",
      TWILIO_VERIFY_SERVICE_SID: "VAtest",
    };
    expect(twilioConfig(all)).toEqual(CFG);
    for (const key of Object.keys(all)) expect(twilioConfig({ ...all, [key]: "" })).toBeNull();
    expect(twilioConfig({})).toBeNull();
  });
});

describe("startVerification", () => {
  test("posts To and Channel=sms to the Verify Service with the API key as basic auth", async () => {
    const r = recorder(201, { sid: "VEx", status: "pending" });
    expect(await startVerification(CFG, "+14155550123", r.fetcher)).toBe("sent");
    const req = r.seen();
    expect(req.url).toBe(`${BASE}/Verifications`);
    expect(req.method).toBe("POST");
    expect(req.headers.get("authorization")).toBe(`Basic ${btoa("SKtest:secret-test")}`);
    expect(req.headers.get("content-type")).toBe("application/x-www-form-urlencoded");
    expect(Object.fromEntries(new URLSearchParams(await req.text()))).toEqual({ To: "+14155550123", Channel: "sms" });
    // A hung Verify call can't hold the consent record's queue for long (review M6).
    expect(req.signal).toBeDefined();
  });

  test("a call past its time is a failure", async () => {
    const slow = (async (_input: RequestInfo | URL, init?: RequestInit) =>
      new Promise<Response>((_resolve, reject) => init?.signal?.addEventListener("abort", () => reject(new Error("aborted"))))) as Fetcher;
    expect(await startVerification(CFG, "+1", slow, 10)).toBe("failed");
    expect(await checkVerification(CFG, "+1", "1", slow, 10)).toBe("failed");
  });

  test("Verify's limits, a number it can't text, and everything else", async () => {
    expect(await startVerification(CFG, "+1", reply(429, { code: 60203 }))).toBe("limited");
    expect(await startVerification(CFG, "+1", reply(429, { code: 20429 }))).toBe("limited");
    expect(await startVerification(CFG, "+1", reply(400, { code: 60203 }))).toBe("limited");
    for (const code of [60200, 60205, 21211, 21614]) expect(await startVerification(CFG, "+1", reply(400, { code }))).toBe("bad_number");
    expect(await startVerification(CFG, "+1", reply(403, { code: 60410 }))).toBe("failed");
    expect(await startVerification(CFG, "+1", reply(500, "not json"))).toBe("failed");
    expect(await startVerification(CFG, "+1", reply(400, { code: "nope" }))).toBe("failed");
    expect(await startVerification(CFG, "+1", down)).toBe("failed");
  });
});

describe("checkVerification", () => {
  test("posts To and Code to VerificationCheck; approved is consent", async () => {
    const r = recorder(200, { status: "approved" });
    expect(await checkVerification(CFG, "+14155550123", "012345", r.fetcher)).toBe("approved");
    const req = r.seen();
    expect(req.url).toBe(`${BASE}/VerificationCheck`);
    expect(req.method).toBe("POST");
    expect(req.headers.get("authorization")).toBe(`Basic ${btoa("SKtest:secret-test")}`);
    expect(Object.fromEntries(new URLSearchParams(await req.text()))).toEqual({ To: "+14155550123", Code: "012345" });
  });

  test("a wrong code stays pending; a gone verification (expired, used up or approved) is expired", async () => {
    expect(await checkVerification(CFG, "+1", "1", reply(200, { status: "pending" }))).toBe("wrong");
    for (const status of ["canceled", "expired", "max_attempts_reached", "deleted", "failed"]) {
      expect(await checkVerification(CFG, "+1", "1", reply(200, { status }))).toBe("expired");
    }
    expect(await checkVerification(CFG, "+1", "1", reply(404, { code: 20404 }))).toBe("expired");
  });

  test("too many tries, and everything else", async () => {
    expect(await checkVerification(CFG, "+1", "1", reply(429, { code: 60202 }))).toBe("limited");
    expect(await checkVerification(CFG, "+1", "1", reply(400, { code: 60202 }))).toBe("limited");
    expect(await checkVerification(CFG, "+1", "1", reply(200, "not json"))).toBe("failed");
    expect(await checkVerification(CFG, "+1", "1", reply(200, { status: 7 }))).toBe("failed");
    expect(await checkVerification(CFG, "+1", "1", reply(500, {}))).toBe("failed");
    expect(await checkVerification(CFG, "+1", "1", down)).toBe("failed");
  });
});
