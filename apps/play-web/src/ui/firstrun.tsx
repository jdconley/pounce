import { nameAllowed } from "@pounce/play-api/names/filter";
import { parseName } from "@pounce/play-api/protocol";
import { useEffect, useRef, useState } from "preact/hooks";

import { art, catArt } from "../lib/art";
import { buzz } from "../lib/haptics";
import { play } from "../lib/sound";
import { bandFor, randomCat, randomName, type AgeBand } from "../store/identity";

import { Button, Cat, catName, Icon } from "./common";

const MIN_YEAR = 1900;

/** "What year were you born?" (AgeGateView.swift): four digits on a keypad, or typed. */
export function AgeScreen(props: { onDone: (band: AgeBand) => void }) {
  const [digits, setDigits] = useState("");
  const [shake, setShake] = useState(0);
  const year = Number(digits);
  const thisYear = new Date().getFullYear();
  const valid = digits.length === 4 && year >= MIN_YEAR && year <= thisYear;

  const press = (d: string) => {
    play("tick", 0.4);
    buzz("tap");
    setDigits((v) => (v.length < 4 ? v + d : v));
  };
  const back = () => setDigits((v) => v.slice(0, -1));
  const done = () => {
    if (!valid) {
      play("nope");
      buzz("nope");
      setShake((n) => n + 1);
      return;
    }
    props.onDone(bandFor(year));
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (/^[0-9]$/.test(e.key)) press(e.key);
      else if (e.key === "Backspace") back();
      else if (e.key === "Enter") done();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  return (
    <main class="screen violet-bg first-run">
      <div class="age">
        <div class="age-badge" aria-hidden="true">
          <svg viewBox="0 0 64 64" width="64" height="64">
            <rect x="12" y="30" width="40" height="22" rx="5" fill="#fff" stroke="#1B0B3A" stroke-width="4" />
            <path d="M12 40h40" stroke="#FF2E9A" stroke-width="5" />
            <rect x="29" y="16" width="6" height="14" rx="2" fill="#FFD21F" stroke="#1B0B3A" stroke-width="3" />
            <path d="M32 6c3 4 3 7 0 9-3-2-3-5 0-9Z" fill="#FF8A00" stroke="#1B0B3A" stroke-width="2.5" />
          </svg>
        </div>
        <h1 class="title outlined" id="age-q">
          What year were you born?
        </h1>
        <div class={`age-slots ${shake ? "nope" : ""}`} key={shake} role="img" aria-label={digits ? `Year: ${digits}` : "No year yet"}>
          {[0, 1, 2, 3].map((i) => (
            <span class={`slot ${i === digits.length ? "next" : ""}`}>{digits[i] ?? ""}</span>
          ))}
        </div>
        <div class="keypad" role="group" aria-labelledby="age-q">
          {["1", "2", "3", "4", "5", "6", "7", "8", "9"].map((d) => (
            <button type="button" class="key" onClick={() => press(d)}>
              {d}
            </button>
          ))}
          <button type="button" class="key teal" aria-label="Delete" onClick={back}>
            <svg viewBox="0 0 32 24" width="34" height="26" aria-hidden="true">
              <path d="M10 2h18a3 3 0 0 1 3 3v14a3 3 0 0 1-3 3H10L1 12Z" fill="#FFD21F" stroke="#1B0B3A" stroke-width="2.5" />
              <path d="M15 8l8 8M23 8l-8 8" stroke="#FF2E9A" stroke-width="3" stroke-linecap="round" />
            </svg>
          </button>
          <button type="button" class="key" onClick={() => press("0")}>
            0
          </button>
          <button type="button" class="key ok" aria-label="Done" disabled={digits.length < 4} onClick={done}>
            <Icon name="icon-check" size={36} />
          </button>
        </div>
      </div>
    </main>
  );
}

export type InviteBanner = { name: string; cat: number; table: string; seatWaits: boolean };

/**
 * The name and the cat, on one screen (first-run funnel, Part 1): a name and a cat already
 * picked, so one tap on the check plays. A guest sees who saved them a seat. A kitten's name
 * comes from the dice only.
 */
export function NameScreen(props: {
  kitten: boolean;
  invite: InviteBanner | null;
  initial?: { name: string; cat: number };
  title?: string;
  onDone: (name: string, cat: number) => void | Promise<void>;
  onCancel?: () => void;
}) {
  const [name, setName] = useState(() => props.initial?.name ?? randomName());
  const [cat, setCat] = useState(() => props.initial?.cat ?? randomCat());
  const [busy, setBusy] = useState(false);
  const [refused, setRefused] = useState(0);
  const input = useRef<HTMLInputElement>(null);
  const clean = parseName(name);
  const ok = clean !== null && nameAllowed(clean);
  const roll = () => {
    play("bat", 0.5);
    buzz("tap");
    setName((n) => randomName(n));
  };
  const done = async () => {
    if (!ok || clean === null) {
      play("nope");
      buzz("nope");
      setRefused((n) => n + 1);
      return;
    }
    setBusy(true);
    try {
      await props.onDone(clean, cat);
    } finally {
      setBusy(false);
    }
  };
  const heading = props.title ?? (props.invite ? `${props.invite.name} saved you a seat` : "What's your name?");
  return (
    <main class="screen violet-bg first-run">
      <form
        class="name-screen"
        onSubmit={(e) => {
          e.preventDefault();
          void done();
        }}
      >
        {props.onCancel ? (
          <button type="button" class="icon-btn back-btn" aria-label="Back" onClick={props.onCancel}>
            <Icon name="icon-back" />
          </button>
        ) : null}
        {props.invite ? (
          <div class="invite-rug" aria-hidden="true">
            <img class="rug-art" src={art("rug")} alt="" />
            <div class="pair">
              <figure>
                <Cat cat={props.invite.cat} pose="awake" />
                <figcaption class="name-tag">{props.invite.name}</figcaption>
              </figure>
              <figure>
                <Cat cat={cat} pose="awake" />
                <figcaption class="name-tag">{clean ?? "You"}</figcaption>
              </figure>
            </div>
          </div>
        ) : (
          <div class="hero-cat">
            <Cat cat={cat} pose="idle" label={`${catName(cat)} cat`} />
          </div>
        )}
        <h1 class="title outlined">{heading}</h1>
        {props.invite?.table ? <p class="chip table-chip">{props.invite.table}</p> : null}
        <div class={`name-row ${refused ? "nope" : ""}`} key={refused}>
          <label class="sr-only" for="name">
            Your name
          </label>
          <input
            id="name"
            ref={input}
            class="field"
            value={name}
            maxLength={20}
            autoComplete="nickname"
            autoCapitalize="words"
            spellcheck={false}
            enterKeyHint="done"
            readOnly={props.kitten}
            aria-invalid={!ok}
            onInput={(e) => setName((e.target as HTMLInputElement).value)}
            onFocus={(e) => (e.target as HTMLInputElement).select()}
          />
          <button type="button" class="icon-btn dice" aria-label="Another name" onClick={roll}>
            <Icon name="icon-dice" />
          </button>
        </div>
        {!ok && clean !== null ? <p class="hint">Try another name.</p> : null}
        <div class="cats" role="radiogroup" aria-label="Your cat">
          {[0, 1, 2, 3, 4, 5, 6, 7].map((c) => (
            <button
              type="button"
              role="radio"
              aria-checked={c === cat}
              aria-label={catName(c)}
              class={`cat-pick ${c === cat ? "on" : ""}`}
              onClick={() => {
                play("pop", 0.5);
                buzz("tap");
                setCat(c);
              }}
            >
              <img src={catArt(c, "idle")} alt="" width={96} height={96} decoding="async" />
            </button>
          ))}
        </div>
        <Button type="submit" variant="ok" size="big" wide class="check" disabled={busy} aria-label="Done">
          <Icon name="icon-check" size={40} />
        </Button>
      </form>
    </main>
  );
}
