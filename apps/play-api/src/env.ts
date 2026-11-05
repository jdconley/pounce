import type { Consents } from "./kittens/consents";
import type { KittenIndex } from "./kittens/kitten-index";
import type { Links } from "./links/links";
import type { Identities } from "./players/identities";
import type { Player } from "./players/player";
import type { DeviceIndex } from "./room/device-index";
import type { GameRoom } from "./room/game-room";
import type { Pair } from "./streaks/pair";

export interface Env {
  ROOMS: DurableObjectNamespace<GameRoom>;
  DEVICES: DurableObjectNamespace<DeviceIndex>;
  PLAYERS: DurableObjectNamespace<Player>;
  /** One instance, named `IDENTITIES_NAME`. */
  IDENTITIES: DurableObjectNamespace<Identities>;
  /** One instance per pair of players, named by pair id (§13.2). */
  PAIRS: DurableObjectNamespace<Pair>;
  /** One instance, named `LINKS_NAME`: pounce ids and Messages link tokens (§13.2). */
  LINKS: DurableObjectNamespace<Links>;
  /** One instance per kitten player: the parent-consent record (consent design §3). */
  CONSENTS: DurableObjectNamespace<Consents>;
  /** One instance, named `KITTENS_NAME`: link codes, kitten ids, parents, text tokens, phone hashes, app transactions. */
  KITTENS: DurableObjectNamespace<KittenIndex>;
  /**
   * Streaks, table looks and Play again (daily habit PR 3) when "on".
   * wrangler.jsonc turns it on in production (and for `wrangler dev`) since
   * the app shipped them (PR 4); Miniflare tests set it themselves.
   */
  STREAKS?: string;
  /**
   * Notifications and Pounce (daily habit PR 5) when "on", and only with
   * `STREAKS` on too. wrangler.jsonc turns it on in production since PR 5's
   * app half shipped the settings panel and Pounce; Miniflare tests set it.
   */
  NOTIFY?: string;
  /**
   * The live table, a Live Activity (daily habit PR 7), when "on", and only with `NOTIFY` on
   * too. wrangler.jsonc turns it on; it's a kill switch for every Live Activity push.
   */
  LIVE?: string;
  /**
   * Parent consent for kittens (daily habit PR 9) when "on", and only with `NOTIFY` on too.
   * wrangler.jsonc turns it on (consent design D4). Off, a kitten's device gets nothing, as before.
   */
  CONSENT?: string;
  /**
   * Twilio, for text plus (consent design D1). Secrets, optional: texting needs all five, so
   * without them consent can't start and nothing is sent. The Auth Token checks STOP webhooks'
   * `X-Twilio-Signature` (plan decision 24); the API key sends.
   */
  TWILIO_ACCOUNT_SID?: string;
  TWILIO_API_KEY_SID?: string;
  TWILIO_API_KEY_SECRET?: string;
  TWILIO_MESSAGING_SERVICE_SID?: string;
  TWILIO_AUTH_TOKEN?: string;
  /** HMAC key for device tokens. A secret; absent until configured. */
  TOKEN_SECRET?: string;
  /** Public TestFlight link for the share page. Optional; the page omits the link when unset. */
  TESTFLIGHT_URL?: string;
  /** APNs auth key, PEM PKCS#8 text. A secret; without it (and the key id) no push is sent. */
  APNS_KEY_P8?: string;
  /** APNs auth key id (the JWT `kid`). A secret. */
  APNS_KEY_ID?: string;
  /** The team id: signs APNs tokens and the Sign in with Apple client secret. */
  APNS_TEAM_ID: string;
  APNS_TOPIC: string;
  APNS_HOST: string;
  /** Sign in with Apple's audience: the app's bundle id. */
  SIWA_CLIENT_ID: string;
  /**
   * Sign in with Apple key, PEM PKCS#8 text, and its id. Secrets, optional: without them sign-in
   * still works, but no refresh token is kept, so nothing can be revoked (§13.1).
   */
  SIWA_KEY_P8?: string;
  SIWA_KEY_ID?: string;
  /**
   * Dev server only (`wrangler dev --var DEV_SPEED:10`, see apps/play-ios/scripts/dev-server.sh):
   * divides the House Cat's think time and the gap before the next round, for fast end-to-end
   * tests. Never set in production: wrangler.jsonc doesn't list it and the deploy sets no such
   * secret (a test checks the config).
   */
  DEV_SPEED?: string;
}

const MAX_DEV_SPEED = 100;

/** `DEV_SPEED` as a factor in 1–100; 1 when unset or unusable. */
export function devSpeed(env: Pick<Env, "DEV_SPEED">): number {
  const speed = Number(env.DEV_SPEED ?? "");
  if (!Number.isFinite(speed) || speed <= 1) return 1;
  return Math.min(speed, MAX_DEV_SPEED);
}
