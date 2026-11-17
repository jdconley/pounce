/**
 * Show on TV: this phone puts its table on a TV by typing the TV's backup code (the six
 * characters under its QR). A TV already showing another table moves only after "Move".
 */
import { useId, useRef, useState } from "preact/hooks";

import { buzz } from "../lib/haptics";
import { play } from "../lib/sound";
import { linkWords, normaliseTvCode, typedTvCode, TV_CODE_LENGTH } from "../lib/tv-code";
import { api } from "../net/api";

import { Button, Sheet } from "./common";

/** A TV with cat ears, drawn like the other choice icons: ink outline, bright fill, a shine. */
export function TvIcon(props: { size?: number }) {
  const id = useId();
  const size = props.size ?? 32;
  return (
    <svg class="tv-icon" width={size} height={size} viewBox="0 0 64 64" aria-hidden="true" focusable="false">
      <defs>
        <linearGradient id={`${id}b`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#ffd84a" />
          <stop offset="1" stop-color="#ff9a00" />
        </linearGradient>
        <linearGradient id={`${id}s`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#6ff3ff" />
          <stop offset="1" stop-color="#1c8df2" />
        </linearGradient>
      </defs>
      <path d="M12 21 L15 6 L27 16 Z M52 21 L49 6 L37 16 Z" fill={`url(#${id}b)`} stroke="#1b0b3a" stroke-width="3.5" stroke-linejoin="round" />
      <rect x="17" y="51" width="8" height="8" rx="3" fill="#1b0b3a" />
      <rect x="39" y="51" width="8" height="8" rx="3" fill="#1b0b3a" />
      <rect x="5" y="15" width="54" height="40" rx="11" fill={`url(#${id}b)`} stroke="#1b0b3a" stroke-width="4" />
      <rect x="12" y="21" width="40" height="28" rx="6" fill={`url(#${id}s)`} stroke="#1b0b3a" stroke-width="3.5" />
      <path d="M17 26 q0-1.5 1.5-1.5 h12 l-13.5 13 z" fill="#fff" opacity="0.6" />
      <path d="M28 29 L39 35 L28 41 Z" fill="#fff" stroke="#1b0b3a" stroke-width="2.5" stroke-linejoin="round" />
    </svg>
  );
}

/** The sheet: the TV's code, then Show; "Move the TV to this table?" when that TV shows another. */
export function ShowOnTvSheet(props: { room: string; onClose: () => void; onShown: () => void }) {
  const [value, setValue] = useState("");
  const [moving, setMoving] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [nope, setNope] = useState(false);
  // A second tap before the re-render that disables Show or Move is still one tap.
  const working = useRef(false);

  const refuse = (words: string) => {
    setError(words);
    setNope(true);
    play("nope");
    buzz("nope");
  };

  const send = async (code: string, move: boolean) => {
    if (working.current) return;
    working.current = true;
    setBusy(true);
    setError(null);
    try {
      const answer = await api.linkScreen({ code }, props.room, move);
      if (answer === "showing") setMoving(code);
      else props.onShown();
    } catch (failure) {
      setMoving(null);
      refuse(linkWords(failure));
    } finally {
      working.current = false;
      setBusy(false);
    }
  };

  if (moving) {
    return (
      <Sheet key="move" title="Move the TV to this table?" onClose={props.onClose}>
        <div class="sheet-actions">
          <Button wide variant="ok" id="tv-move" disabled={busy} onClick={() => void send(moving, true)}>
            Move
          </Button>
          <Button wide variant="violet" onClick={props.onClose}>
            Cancel
          </Button>
        </div>
      </Sheet>
    );
  }

  return (
    <Sheet key="code" title="Show on TV" onClose={props.onClose}>
      <form
        class="sheet-actions tv-code-form"
        onSubmit={(e) => {
          e.preventDefault();
          const code = normaliseTvCode(value);
          if (code) void send(code, false);
          else refuse("No TV with that code.");
        }}
      >
        <label class="field-label" for="tv-code">
          TV code
        </label>
        <input
          id="tv-code"
          class={`field code-field tv-code-field ${nope ? "nope" : ""}`}
          value={value}
          autoComplete="off"
          autoCapitalize="characters"
          autoCorrect="off"
          spellcheck={false}
          inputMode="text"
          enterKeyHint="go"
          aria-invalid={error ? true : undefined}
          aria-describedby={error ? "tv-code-error" : undefined}
          onInput={(e) => {
            const input = e.target as HTMLInputElement;
            const next = typedTvCode(input.value);
            // Keep the field what it shows, even when a typed character was dropped.
            if (input.value !== next) input.value = next;
            setValue(next);
            setError(null);
          }}
          onAnimationEnd={() => setNope(false)}
        />
        <p class={`link-error ${error ? "" : "empty"}`} id="tv-code-error" role="alert">
          {error ?? ""}
        </p>
        <Button type="submit" wide variant="ok" id="tv-show" disabled={busy || value.length < TV_CODE_LENGTH}>
          Show
        </Button>
      </form>
    </Sheet>
  );
}
