/**
 * Sniff's board and controls inside the Dish's puzzle screen (the host draws the top bar, the
 * clock and the end): six trails of scent tags over Sniff's own keyboard. A hardware keyboard
 * types too. The allowed list loads lazily, in its own chunk; checking a word is a binary search.
 */
import { useEffect, useRef, useState } from "preact/hooks";

import { buzz } from "../../lib/haptics";
import { play } from "../../lib/sound";

import { deleteLetter, emptyBoard, isOver, keys, refused, reveal, submit, typeLetter, type SniffBoard } from "./board";
import { SniffKeys } from "./keys";
import { SniffTrail } from "./trail";

import type { SniffReveal } from "@pounce/play-api/daily/sniff/types";


/** Who answers a guess: the server through the Dish's run session, or the demo. Null: not taken, try again. */
export type SniffReferee = (word: string) => Promise<SniffReveal | null>;

let allowedCheck: Promise<(word: string) => boolean> | null = null;
/** The allowed-word check, loaded once and kept. */
export function loadAllowed(): Promise<(word: string) => boolean> {
  allowedCheck ??= import("@pounce/play-api/daily/sniff/allowed-check").then((m) => (w: string) => m.isAllowed(w));
  return allowedCheck;
}

export function SniffPlay(props: {
  start?: SniffBoard;
  referee: SniffReferee;
  /** False once the host says the run has ended: no more input. */
  enabled?: boolean;
  onEnd?: (board: SniffBoard) => void;
}) {
  const enabled = props.enabled ?? true;
  const [board, setBoard] = useState<SniffBoard>(props.start ?? emptyBoard());
  const [allowed, setAllowed] = useState<((word: string) => boolean) | null>(null);
  const [shake, setShake] = useState(0);
  const [note, setNote] = useState<string | null>(null);
  const live = useRef(board);
  live.current = board;

  useEffect(() => {
    let on = true;
    void loadAllowed().then((check) => on && setAllowed(() => check));
    return () => {
      on = false;
    };
  }, []);

  const update = (next: SniffBoard) => {
    live.current = next;
    setBoard(next);
  };

  const refuse = (words: string) => {
    setShake((n) => n + 1);
    setNote(words);
    play("nope", 0.6);
    buzz("nope");
  };

  const send = () => {
    if (!allowed) return;
    const s = submit(live.current, allowed);
    if (s.outcome === "unknown") return refuse("Not a word");
    if (s.outcome === "short") return refuse("Five letters");
    if (s.outcome !== "send") return;
    update(s.board);
    play("whoosh", 0.5);
    void props.referee(s.word).then((r) => {
      if (!r) return update(refused(live.current));
      const next = reveal(live.current, r);
      update(next);
      const solved = r.marks.every((m) => m === "spot");
      play(solved ? "fanfare" : "flip", 0.6);
      buzz(solved ? "win" : "drop");
      if (isOver(next)) props.onEnd?.(next);
    });
  };
  const type = (letter: string) => {
    setNote(null);
    update(typeLetter(live.current, letter));
  };
  const del = () => {
    setNote(null);
    update(deleteLetter(live.current));
  };

  const handlers = useRef({ send, type, del, enabled });
  handlers.current = { send, type, del, enabled };
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey || !handlers.current.enabled) return;
      if (e.key === "Enter") handlers.current.send();
      else if (e.key === "Backspace") handlers.current.del();
      else if (/^[a-zA-Z]$/.test(e.key)) handlers.current.type(e.key);
      else return;
      e.preventDefault();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const over = isOver(board);
  return (
    <div class="sniff sniff-play">
      <div class="sniff-board">
        <SniffTrail board={board} shake={shake} />
      </div>
      <div class="sniff-note" role="status" aria-live="polite">
        {note && (
          <span key={shake} onAnimationEnd={() => setNote(null)}>
            {note}
          </span>
        )}
      </div>
      {!over && (
        <SniffKeys
          marks={keys(board)}
          enabled={enabled && board.pending === null}
          canSend={allowed !== null && board.draft.length === 5}
          onLetter={type}
          onDelete={del}
          onSend={send}
        />
      )}
    </div>
  );
}
