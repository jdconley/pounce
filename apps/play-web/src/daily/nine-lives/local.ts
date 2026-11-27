/**
 * Plays Nine Lives with no server, for the views before the Daily Dish host exists. It knows the
 * sample's solution, which no real client ever does: real hints come from the server.
 */
import type { MoveReveal } from "./model";
import type { NineLivesMove, NineLivesState } from "@pounce/play-api/daily/nine-lives/grid";

/** Where a board's moves go: the Daily Dish host's run session (`dish.tsx`), or this local stand-in. */
export interface NineLivesDriver {
  /**
   * A move the board already shows. Sent on; never awaited by a click. `urgent`: send it now (the
   * move that fills the grid, and every set under the lives rules), so the server's answer comes
   * at once. Resolves once the server has answered the batch that carried it.
   */
  send(move: NineLivesMove, urgent: boolean): Promise<unknown> | void;
  /** The server's hint: the cell and digit, or null when there is none. */
  hint(): Promise<{ i: number; d: number } | null>;
  /** Hears the server's board when it replaces ours (a refused batch). Returns the unsubscribe. */
  resyncs?(listener: (state: NineLivesState) => void): () => void;
  /** Hears what the server's answers to moves reveal (lives: wrong numbers, the solution). */
  reveals?(listener: (reveal: MoveReveal) => void): () => void;
}

const digits = (text: string): number[] => [...text].map(Number);

/** The server's pinned Monday sample (`apps/play-api/src/daily/nine-lives/samples.ts`). */
export const SAMPLE_GIVENS = digits("600350270050900130030804906400000003080000020500000009301205080025008040064073002");
export const SAMPLE_SOLUTION = digits("649351278258967134137824956412589763983716425576432819391245687725698341864173592");

export class LocalDriver implements NineLivesDriver {
  readonly sent: NineLivesMove[] = [];
  private cells = [...SAMPLE_GIVENS];

  send(move: NineLivesMove): void {
    this.sent.push(move);
    this.cells[move.i] = move.k === "set" ? move.d : 0;
  }

  async hint(): Promise<{ i: number; d: number } | null> {
    const i = this.cells.findIndex((d, k) => d !== SAMPLE_SOLUTION[k]);
    if (i < 0) return null;
    this.cells[i] = SAMPLE_SOLUTION[i]!;
    return { i, d: SAMPLE_SOLUTION[i]! };
  }
}
