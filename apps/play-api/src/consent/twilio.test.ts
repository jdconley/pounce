import { describe, expect, test } from "vitest";

import { OPTED_OUT, sendText, twilioConfig, twilioSignature, verifyTwilio } from "./twilio";

// Twilio's documented example (its helper libraries' webhook tests). Fixture values, not real ones.
const TOKEN = "12345";
const URL_ = "https://mycompany.com/myapp.php?foo=1&bar=2";
const PARAMS: [string, string][] = [
  ["CallSid", "CA1234567890ABCDE"],
  ["Caller", "+14158675309"],
  ["Digits", "1234"],
  ["From", "+14158675309"],
  ["To", "+18005551212"],
];
const SIGNATURE = "RSOYDt4T1cUTdK1PDd93/VVr8B8=";

const CFG = { accountSid: "ACtest", apiKeySid: "SKtest", apiKeySecret: "secret-test", messagingServiceSid: "MGtest", authToken: "auth-test" };

describe("twilioConfig", () => {
  test("needs all five secrets", () => {
    const all = {
      TWILIO_ACCOUNT_SID: "ACtest",
      TWILIO_API_KEY_SID: "SKtest",
      TWILIO_API_KEY_SECRET: "secret-test",
      TWILIO_MESSAGING_SERVICE_SID: "MGtest",
      TWILIO_AUTH_TOKEN: "auth-test",
    };
    expect(twilioConfig(all)).toEqual(CFG);
    for (const key of Object.keys(all)) expect(twilioConfig({ ...all, [key]: "" })).toBeNull();
    expect(twilioConfig({})).toBeNull();
  });
});

describe("X-Twilio-Signature", () => {
  test("matches Twilio's documented example, whatever the field order", async () => {
    expect(await twilioSignature(TOKEN, URL_, PARAMS)).toBe(SIGNATURE);
    expect(await twilioSignature(TOKEN, URL_, [...PARAMS].reverse())).toBe(SIGNATURE);
    expect(await verifyTwilio(TOKEN, URL_, PARAMS, SIGNATURE)).toBe(true);
  });

  test("repeated names sort by value", async () => {
    const a = await twilioSignature(TOKEN, URL_, [["A", "2"], ["A", "1"], ["B", "x"]]);
    expect(await twilioSignature(TOKEN, URL_, [["B", "x"], ["A", "1"], ["A", "2"]])).toBe(a);
    expect(await twilioSignature(TOKEN, URL_, [["A", "1"], ["A", "1"]])).toBe(await twilioSignature(TOKEN, URL_, [["A", "1"], ["A", "1"]]));
  });

  test("refuses a missing or wrong signature, a changed URL, field or token", async () => {
    expect(await verifyTwilio(TOKEN, URL_, PARAMS, null)).toBe(false);
    expect(await verifyTwilio(TOKEN, URL_, PARAMS, "")).toBe(false);
    expect(await verifyTwilio(TOKEN, URL_, PARAMS, SIGNATURE.slice(0, -2))).toBe(false);
    expect(await verifyTwilio(TOKEN, URL_, PARAMS, `${SIGNATURE}AA`)).toBe(false);
    expect(await verifyTwilio(TOKEN, `${URL_}&x=1`, PARAMS, SIGNATURE)).toBe(false);
    expect(await verifyTwilio(TOKEN, URL_, [...PARAMS.slice(1), ["CallSid", "CA0"]], SIGNATURE)).toBe(false);
    expect(await verifyTwilio("54321", URL_, PARAMS, SIGNATURE)).toBe(false);
  });
});

describe("sendText", () => {
  test("posts the Messages form with the API key as basic auth", async () => {
    let seen: Request | null = null;
    const fetcher = (async (input: RequestInfo | URL, init?: RequestInit) => {
      seen = new Request(input, init);
      return new Response(JSON.stringify({ sid: "SMx" }), { status: 201 });
    }) as typeof fetch;
    expect(await sendText(CFG, "+15551234567", "Hello & bye", fetcher)).toEqual({ ok: true });
    const req = seen as unknown as Request;
    expect(req.url).toBe("https://api.twilio.com/2010-04-01/Accounts/ACtest/Messages.json");
    expect(req.method).toBe("POST");
    expect(req.headers.get("authorization")).toBe(`Basic ${btoa("SKtest:secret-test")}`);
    expect(req.headers.get("content-type")).toBe("application/x-www-form-urlencoded");
    const form = new URLSearchParams(await req.text());
    expect(Object.fromEntries(form)).toEqual({ To: "+15551234567", MessagingServiceSid: "MGtest", Body: "Hello & bye" });
  });

  test("reports Twilio's error code, a body without one, and a network failure", async () => {
    const reply = (status: number, body: string) => (async () => new Response(body, { status })) as unknown as typeof fetch;
    expect(await sendText(CFG, "+1", "x", reply(400, JSON.stringify({ code: OPTED_OUT })))).toEqual({ ok: false, status: 400, code: 21610 });
    expect(await sendText(CFG, "+1", "x", reply(500, JSON.stringify({ code: "nope" })))).toEqual({ ok: false, status: 500, code: null });
    expect(await sendText(CFG, "+1", "x", reply(502, "not json"))).toEqual({ ok: false, status: 502, code: null });
    const down = (async () => {
      throw new Error("offline");
    }) as unknown as typeof fetch;
    expect(await sendText(CFG, "+1", "x", down)).toEqual({ ok: false, status: 0, code: null });
  });
});
