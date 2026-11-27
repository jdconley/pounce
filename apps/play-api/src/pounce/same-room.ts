import { sameRoomGame } from "../games";

import type { Env } from "../env";

/**
 * Whether the table `code` is of a same-room game (Purrtrait), as the room itself says: no request
 * to play goes to one (design §5.1). A room that fails to answer counts as not same-room, so a
 * passing hiccup never fails a Cat Tower pounce.
 */
export async function sameRoomTable(env: Env, code: string): Promise<boolean> {
  try {
    const room = await env.ROOMS.get(env.ROOMS.idFromName(code)).invite();
    return room !== null && sameRoomGame(room.game);
  } catch {
    return false;
  }
}
