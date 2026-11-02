import type { DeviceIndex } from "./room/device-index";
import type { GameRoom } from "./room/game-room";

export interface Env {
  ROOMS: DurableObjectNamespace<GameRoom>;
  DEVICES: DurableObjectNamespace<DeviceIndex>;
  /** HMAC key for device tokens. A secret; absent until configured. */
  TOKEN_SECRET?: string;
  /** Public TestFlight link for the share page. Optional; the page omits the link when unset. */
  TESTFLIGHT_URL?: string;
  /** APNs auth key, PEM PKCS#8 text. A secret; without it (and the key id) no push is sent. */
  APNS_KEY_P8?: string;
  /** APNs auth key id (the JWT `kid`). A secret. */
  APNS_KEY_ID?: string;
  APNS_TEAM_ID: string;
  APNS_TOPIC: string;
  APNS_HOST: string;
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
