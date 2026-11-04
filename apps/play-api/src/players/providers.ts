import { exchangeAppleCode, parseAppleProof, revokeAppleToken, verifyAppleToken } from "./apple";
import { PERSON_ID } from "./ids";

import type { Env } from "../env";

export type ProviderId = "device" | "apple";

/** A verified claim. `nonce` is the token's nonce hash, used once; `secret` is what `revoke` needs. */
export type Verified = { subject: string; secret?: string; nonce?: { hash: string; expiresAt: number } };

/**
 * One way to prove who you are (§13.1). Adding Google, email or passkeys later
 * means one more of these, with no data migration.
 */
export type IdentityProvider = {
  id: ProviderId;
  /** Offered by POST /v1/identities/{provider}; `device` binds through the profile instead. */
  signIn: boolean;
  verify(proof: unknown, env: Env, fetcher: typeof fetch, nowSec: number): Promise<Verified | null>;
  revoke?(secret: string, env: Env, fetcher: typeof fetch, nowSec: number): Promise<void>;
};

const device: IdentityProvider = {
  id: "device",
  signIn: false,
  // The person key is checked against its stored hash by the identities index.
  async verify(proof) {
    const id = (proof as { id?: unknown } | null)?.id;
    return typeof id === "string" && PERSON_ID.test(id) && typeof (proof as { key?: unknown }).key === "string"
      ? { subject: id }
      : null;
  },
};

const apple: IdentityProvider = {
  id: "apple",
  signIn: true,
  async verify(proof, env, fetcher, nowSec) {
    const parsed = parseAppleProof(proof);
    if (!parsed) return null;
    const claims = await verifyAppleToken(parsed.identityToken, {
      clientId: env.SIWA_CLIENT_ID,
      nonce: parsed.nonce,
      nowSec,
      fetcher,
    });
    if (!claims) return null;
    const secret = parsed.authorizationCode
      ? await exchangeAppleCode(env, parsed.authorizationCode, fetcher, nowSec)
      : null;
    return {
      subject: claims.sub,
      ...(secret ? { secret } : {}),
      // The claim, not the raw nonce: a replayed token carries the same one.
      nonce: { hash: claims.nonce, expiresAt: claims.exp * 1000 },
    };
  },
  revoke: (secret, env, fetcher, nowSec) => revokeAppleToken(env, secret, fetcher, nowSec),
};

const PROVIDERS = new Map<string, IdentityProvider>([
  ["device", device],
  ["apple", apple],
]);

export function provider(id: string): IdentityProvider | null {
  return PROVIDERS.get(id) ?? null;
}
