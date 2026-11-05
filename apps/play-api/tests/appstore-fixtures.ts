import { readFileSync } from "node:fs";

import { base64url, pemBody } from "../src/players/ids";

/** The test-only App Store chain in `fixtures/appstore` (see its README): never Apple's, never real. */

export const pem = (name: string): string => readFileSync(new URL(`../fixtures/appstore/${name}.pem`, import.meta.url), "utf8");

/** A fixture certificate as an `x5c` entry: base64 DER. */
export const der64 = (name: string): string =>
  pem(name)
    .replace(/-----[A-Z ]+-----/g, "")
    .replace(/\s+/g, "");

export const TEST_ROOTS = [der64("root")];
export const GOOD_CHAIN = ["leaf", "intermediate", "root"];

const encoder = new TextEncoder();
const part = (v: unknown) => base64url(encoder.encode(JSON.stringify(v)));

/** A JWS like the App Store's, signed by a fixture leaf's key. */
export async function signJws(
  payload: unknown,
  options: { chain?: string[]; key?: "leaf" | "leaf-p384"; alg?: string } = {},
): Promise<string> {
  const keyName = options.key ?? "leaf";
  const curve = keyName === "leaf" ? "P-256" : "P-384";
  const key = await crypto.subtle.importKey("pkcs8", pemBody(pem(`${keyName}.p8`)), { name: "ECDSA", namedCurve: curve }, false, ["sign"]);
  const input = `${part({ alg: options.alg ?? "ES256", x5c: (options.chain ?? GOOD_CHAIN).map(der64) })}.${part(payload)}`;
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(input)));
  return `${input}.${base64url(sig)}`;
}

/** A `RESCIND_CONSENT` notification body for `appTransactionId`, signed like Apple's. */
export async function rescindBody(
  appTransactionId: string,
  over: { bundleId?: string; environment?: string; type?: string; inner?: string } = {},
): Promise<{ signedPayload: string }> {
  const bundleId = over.bundleId ?? "com.conleychaos.play";
  const inner =
    over.inner ??
    (await signJws({ appTransactionId, bundleId, originalPlatform: "iOS", receiptType: over.environment ?? "Production" }));
  return {
    signedPayload: await signJws({
      notificationType: over.type ?? "RESCIND_CONSENT",
      notificationUUID: crypto.randomUUID(),
      version: "2.0",
      signedDate: Date.now(),
      appData: { bundleId, environment: over.environment ?? "Production", signedAppTransactionInfo: inner },
    }),
  };
}
