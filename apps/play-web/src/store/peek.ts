/**
 * A seatless look at an invite's table (InviteHost.swift): who saved a guest a seat. Opens the
 * room's socket, reads the first snapshot, and closes. Null after 6 s or on any trouble.
 */
import { api } from "../net/api";
import { RoomSocket } from "../net/socket";

import { inviteHost } from "./lobby";

export type InviteBanner = { name: string; cat: number; table: string; seatWaits: boolean };

const PEEK_MS = 6000;

export function peekInvite(code: string): Promise<InviteBanner | null> {
  return new Promise((resolve) => {
    const socket = new RoomSocket({ code, token: async () => (await api.credential()).token, backoff: [] });
    const done = (value: InviteBanner | null) => {
      clearTimeout(timer);
      socket.stop();
      resolve(value);
    };
    const timer = setTimeout(() => done(null), PEEK_MS);
    socket.on((e) => {
      if (e.kind === "message" && e.message.t === "snapshot") done(inviteHost(e.message.room));
      else if (e.kind === "notFound" || e.kind === "locked" || e.kind === "closed" || e.kind === "refused" || e.kind === "disconnected") done(null);
    });
    socket.start();
  });
}
