/**
 * Sniff's own keyboard: chunky candy keys that carry the server's marks as the tags do (a filled
 * paw, an outlined paw, or dimmed), Delete at the end of the last row, and a wide Sniff button.
 */

import { buzz } from "../../lib/haptics";

import { Paw } from "./trail";

import type { Mark } from "@pounce/play-api/daily/sniff/types";

const ROWS = ["qwertyuiop", "asdfghjkl", "zxcvbnm"];
const SPOKEN: Record<Mark, string> = { spot: "right spot", near: "elsewhere", none: "not in the word" };

export function SniffKeys(props: {
  marks: Partial<Record<string, Mark>>;
  enabled: boolean;
  canSend: boolean;
  onLetter: (letter: string) => void;
  onDelete: () => void;
  onSend: () => void;
}) {
  const press = (fn: () => void) => () => {
    buzz("tap");
    fn();
  };
  return (
    <div class="sniff-keys" role="group" aria-label="Keyboard">
      {ROWS.map((row, r) => (
        <div class="sniff-key-row" key={row}>
          {[...row].map((letter) => {
            const mark = props.marks[letter];
            return (
              <button
                type="button"
                class="sniff-key"
                data-mark={mark}
                disabled={!props.enabled}
                aria-label={mark ? `${letter.toUpperCase()}, ${SPOKEN[mark]}` : letter.toUpperCase()}
                onPointerDown={(e) => e.preventDefault()}
                onClick={press(() => props.onLetter(letter))}
                key={letter}
              >
                {letter.toUpperCase()}
                {(mark === "spot" || mark === "near") && <Paw filled={mark === "spot"} />}
              </button>
            );
          })}
          {r === ROWS.length - 1 && (
            <button
              type="button"
              class="sniff-key delete"
              disabled={!props.enabled}
              aria-label="Delete"
              onPointerDown={(e) => e.preventDefault()}
              onClick={press(props.onDelete)}
            >
              <svg viewBox="0 0 24 24" aria-hidden="true">
                <path d="M9 4h11a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H9l-7-8z M12 9l6 6 M18 9l-6 6" />
              </svg>
            </button>
          )}
        </div>
      ))}
      <button
        type="button"
        class="sniff-send"
        data-ready={props.canSend ? "" : undefined}
        disabled={!props.enabled}
        onPointerDown={(e) => e.preventDefault()}
        onClick={press(props.onSend)}
      >
        <Paw filled />
        Sniff
      </button>
    </div>
  );
}
