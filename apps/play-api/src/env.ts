import type { Consents } from "./kittens/consents";
import type { KittenIndex } from "./kittens/kitten-index";
import type { Links } from "./links/links";
import type { Identities } from "./players/identities";
import type { Player } from "./players/player";
import type { DeviceIndex } from "./room/device-index";
import type { GameRoom } from "./room/game-room";
import type { Limiter } from "./safety/limiter";
import type { Reports } from "./safety/reports";
import type { Pair } from "./streaks/pair";

export interface Env {
  /**
   * The static assets in ./public (wrangler.jsonc `assets`). The Worker reads only the landing
   * page's clip through it (`/media/*`, src/http/media.ts); images are served without the Worker.
   * Absent in Miniflare tests that mount no assets.
   */
  ASSETS?: Fetcher;
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
  /** One instance per limited key (an address, a device): counters that hold across isolates. */
  LIMITS: DurableObjectNamespace<Limiter>;
  /** One instance, named `REPORTS_NAME`: every player report. */
  REPORTS: DurableObjectNamespace<Reports>;
  /**
   * The owner's key for `GET /v1/admin/reports`. A secret, optional: without it that route is a
   * 404 and reports are read in the Cloudflare dashboard instead.
   */
  REPORTS_KEY?: string;
  /**
   * The first-run funnel's database (src/funnel, docs/funnel.md): when each anonymous device first
   * reached each step. Optional: without it (Miniflare tests that bind none) nothing is recorded.
   */
  FUNNEL?: D1Database;
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
   * Your own streak, the trophy room and connections on accept (trophy room design §5) when
   * "on", and only with `STREAKS` on too. wrangler.jsonc turns it on.
   */
  TROPHY?: string;
  /** The bad connection indicator's server half (`linkOn`). */
  LINK?: string;
  /**
   * Nudges (`nudgeOn`): a player asks the one whose move it is to take it, in the app and,
   * with `NOTIFY` on too, by push. wrangler.jsonc turns it on; off, `nudge` is refused and
   * snapshots carry no `nudge`, as before.
   */
  NUDGE?: string;
  /**
   * The games rooms may be created for beyond Cat Tower: a comma-separated list of game ids
   * (`gamesOn` in src/games, e.g. "tiles"). Empty or unset, as in production's wrangler.jsonc
   * today, only Cat Tower: asking for any other game is refused, as it always was. Tests and
   * local dev (`.dev.vars`) turn the tile game on.
   */
  GAMES?: string;
  /**
   * Twilio Verify, for parent consent (consent design D1, D6). Secrets, optional: all four or
   * nothing is sent, so consent can't start. Verify texts a six-digit code from Twilio's own
   * pre-registered senders, so Pounce needs no phone number of its own and no 10DLC.
   */
  TWILIO_ACCOUNT_SID?: string;
  TWILIO_API_KEY_SID?: string;
  TWILIO_API_KEY_SECRET?: string;
  TWILIO_VERIFY_SERVICE_SID?: string;
  /** HMAC key for device tokens. A secret; absent until configured. */
  TOKEN_SECRET?: string;
  /**
   * The public TestFlight beta (wrangler.jsonc). Used only while `APP_STORE_URL` is empty: the
   * landing page's beta button, `/get`, and the invite pages' "Get the app". Optional.
   */
  TESTFLIGHT_URL?: string;
  /**
   * The App Store listing, `https://apps.apple.com/app/id<number>` (wrangler.jsonc). The invite
   * pages' "Get the app" goes there, and its numeric id turns on Safari's Smart App Banner. Empty
   * until the App Store id is known: no banner, and the button falls back to `TESTFLIGHT_URL`.
   */
  APP_STORE_URL?: string;
  /**
   * The oldest app version the server still supports (app updates design §3), e.g. "1.1". Empty
   * or unset, as in wrangler.jsonc today: every version. An app below it is told to update, but
   * only once the App Store has a version at least this new (`enforcedMinimum`).
   */
  APP_MINIMUM?: string;
  /**
   * `on`: enforce `APP_MINIMUM` whatever Apple's lookup says. Unset, as in wrangler.jsonc: the
   * minimum waits for Apple to name a version that new, and `APP_LATEST` can't stand in for that.
   */
  APP_MINIMUM_FORCE?: string;
  /**
   * Overrides the version apps are told is the newest (`GET /v1/app`'s `latest`, for the soft
   * card): a version ("1.2"), or "off" for "say nothing". Empty or unset: what Apple's public
   * lookup last said. It never lets `APP_MINIMUM` turn anyone away, and no update push goes by it.
   */
  APP_LATEST?: string;
  /** "off": never ask Apple's lookup (then only `APP_LATEST` says what is live). */
  APP_LOOKUP?: string;
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

/**
 * Heartbeats, move acks and each seat's connection quality (the bad connection
 * indicator) when "on". wrangler.jsonc turns it on; off, snapshots carry no
 * `link` and apps behave as before.
 */
export function linkOn(env: Pick<Env, "LINK">): boolean {
  return ["on", "1", "true"].includes((env.LINK ?? "").toLowerCase());
}

/** Nudges when "on" (see `Env.NUDGE`). The push half also needs `NOTIFY` (`notifyOn`). */
export function nudgeOn(env: Pick<Env, "NUDGE">): boolean {
  return ["on", "1", "true"].includes((env.NUDGE ?? "").toLowerCase());
}
