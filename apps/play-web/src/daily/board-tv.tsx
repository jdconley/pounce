/**
 * "Show board on TV" (spec §8, the phone's side): type the TV's backup code, or open the TV's QR
 * (the TV-link page offers the board there), and that TV shows this person's board every evening
 * for 30 days. Unlink makes every TV showing it forget.
 */
import { useRef, useState } from "preact/hooks";

import { buzz } from "../lib/haptics";
import { play } from "../lib/sound";
import { linkWords, normaliseTvCode, typedTvCode, TV_CODE_LENGTH } from "../lib/tv-code";
import { api } from "../net/api";
import { Button, Sheet } from "../ui/common";

import { dailyPath } from "./client";

/** Puts `person`'s board on the TV that showed `body`'s QR token or backup code. */
export async function linkBoard(body: { token: string } | { code: string }, person: string): Promise<void> {
  await api.call("POST", dailyPath("/v1/screens/link", person), { ...body, board: true });
}

/** Every TV showing `person`'s board forgets it. */
export async function unlinkBoard(person: string): Promise<void> {
  await api.call("DELETE", dailyPath("/v1/daily/board/tv", person));
}

export function BoardTvSheet(props: { person: string; onClose: () => void; onShown: () => void }) {
  const [value, setValue] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [nope, setNope] = useState(false);
  const working = useRef(false);

  const refuse = (words: string) => {
    setError(words);
    setNope(true);
    play("nope");
    buzz("nope");
  };

  const send = async (code: string) => {
    if (working.current) return;
    working.current = true;
    setBusy(true);
    setError(null);
    try {
      await linkBoard({ code }, props.person);
      props.onShown();
    } catch (failure) {
      refuse(linkWords(failure));
    } finally {
      working.current = false;
      setBusy(false);
    }
  };

  return (
    <Sheet title="Show board on TV" onClose={props.onClose}>
      <form
        class="sheet-actions tv-code-form"
        onSubmit={(e) => {
          e.preventDefault();
          const code = normaliseTvCode(value);
          if (code) void send(code);
          else refuse("No TV with that code.");
        }}
      >
        <label class="field-label" for="board-tv-code">
          TV code
        </label>
        <input
          id="board-tv-code"
          class={`field code-field tv-code-field ${nope ? "nope" : ""}`}
          value={value}
          autoComplete="off"
          autoCapitalize="characters"
          autoCorrect="off"
          spellcheck={false}
          inputMode="text"
          enterKeyHint="go"
          aria-invalid={error ? true : undefined}
          aria-describedby={error ? "board-tv-error" : undefined}
          onInput={(e) => {
            const input = e.target as HTMLInputElement;
            const next = typedTvCode(input.value);
            if (input.value !== next) input.value = next;
            setValue(next);
            setError(null);
          }}
          onAnimationEnd={() => setNope(false)}
        />
        <p class={`link-error ${error ? "" : "empty"}`} id="board-tv-error" role="alert">
          {error ?? ""}
        </p>
        <Button type="submit" wide variant="ok" id="board-tv-show" disabled={busy || value.length < TV_CODE_LENGTH}>
          Show
        </Button>
      </form>
    </Sheet>
  );
}
