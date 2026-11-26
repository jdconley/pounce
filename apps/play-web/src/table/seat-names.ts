/** Who sits at a seat, in words and as a cat: pure, so the move rules and the UI share it. */
import type { RoomView } from "@pounce/play-api/protocol";

export type SeatInfo = RoomView["seats"][number];

/**
 * A seat's display name: the person's, "House Cat", or nothing for an empty seat. A seat a House
 * Cat took over when its person left (Birdwatch) keeps that person's name tag.
 */
export const seatName = (s: SeatInfo | undefined): string => (s?.kind === "bot" && !s.left ? "House Cat" : (s?.person?.name ?? ""));

/** The House Cat is the gray cat; a seat it took over keeps its person's cat. */
export const seatCat = (s: SeatInfo | undefined): number => (s?.kind === "bot" && !s.left ? 3 : (s?.person?.cat ?? 0));

/** A seat someone plays in: a person or a House Cat, not an open or closed one. */
export const playing = (s: SeatInfo | undefined): boolean => s?.kind === "human" || s?.kind === "bot";
