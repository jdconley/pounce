#!/usr/bin/env node
/**
 * Makes the web player's push key pair (VAPID, P-256) and stores it as the two GitHub Actions
 * secrets the deploy syncs to the Worker: PLAY_API_VAPID_PUBLIC_KEY and PLAY_API_VAPID_PRIVATE_KEY.
 * The private key goes straight to `gh secret set` on stdin; it is never printed or written to a
 * file. Run once, from the repo, signed in to gh with access to it:
 *
 *   node apps/play-api/scripts/vapid-keys.mjs
 *
 * Making a new pair later unsubscribes every browser (their subscriptions are tied to the old
 * public key); they ask again the next time someone turns alerts on.
 */
import { execFileSync } from "node:child_process";
import { webcrypto } from "node:crypto";

const b64url = (bytes) => Buffer.from(bytes).toString("base64url");

const pair = await webcrypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const publicKey = b64url(new Uint8Array(await webcrypto.subtle.exportKey("raw", pair.publicKey)));
const privateKey = (await webcrypto.subtle.exportKey("jwk", pair.privateKey)).d;

for (const [name, value] of [["PLAY_API_VAPID_PUBLIC_KEY", publicKey], ["PLAY_API_VAPID_PRIVATE_KEY", privateKey]]) {
  execFileSync("gh", ["secret", "set", name], { input: value, stdio: ["pipe", "inherit", "inherit"] });
}
console.log("Set PLAY_API_VAPID_PUBLIC_KEY and PLAY_API_VAPID_PRIVATE_KEY. The next deploy turns web push on.");
