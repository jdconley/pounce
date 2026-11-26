/**
 * Birdwatch's controls, one step at a time (design §5.3, §5.4): the bid sign with +5, Bid and
 * Pass; the nest's Done; the four trump suits; the 5-player partner call; the between-hands
 * summary and the score sheet. Each is enabled from what the server sent (`bidRange`,
 * `partnerChoices`): the rules stay on the server.
 */
import { useEffect, useRef, useState } from "preact/hooks";

import { buzz } from "../lib/haptics";
import { play } from "../lib/sound";
import { Button, Sheet } from "../ui/common";

import { BirdFace, SuitIcon } from "./bw-faces";
import { cardLabel, lastHand, partnerRows, sideName, signed, SUIT_WORD, SUITS, type CardId, type RuleSetId, type Suit } from "./bw-model";
import { seatName } from "./seat";

import type { RoomView } from "@pounce/play-api/protocol";

const SUIT_NAME: Record<Suit, string> = { fish: "Fish", mouse: "Mouse", feather: "Feather", bell: "Bell" };

/** Repeats `fn` while held: once at the press, then every 140 ms after 400 ms. Frames, not timers. */
function useHold(fn: () => void) {
  const live = useRef(fn);
  live.current = fn;
  const frame = useRef(0);
  const stop = () => {
    if (frame.current) cancelAnimationFrame(frame.current);
    frame.current = 0;
  };
  useEffect(() => stop, []);
  const start = (e: PointerEvent) => {
    if (e.button !== 0 && e.pointerType === "mouse") return;
    stop();
    live.current();
    const t0 = performance.now();
    let last = t0;
    const tick = (now: number) => {
      if (now - t0 >= 400 && now - last >= 140) {
        last = now;
        live.current();
      }
      frame.current = requestAnimationFrame(tick);
    };
    frame.current = requestAnimationFrame(tick);
  };
  return { onPointerDown: start, onPointerUp: stop, onPointerLeave: stop, onPointerCancel: stop };
}

/** The bid: one big number on the sign, +5 (hold to raise faster), Bid and Pass. */
export function BidPanel(props: {
  range: { min: number; max: number; step: number };
  amount: number;
  setAmount: (n: number | ((a: number) => number)) => void;
  onBid: () => void;
  onPass: () => void;
  busy: boolean;
}) {
  const { range, amount } = props;
  const raise = () => {
    if (amount + range.step > range.max) {
      play("nope", 0.4);
      return;
    }
    props.setAmount((a) => Math.min(Math.max(a, range.min) + range.step, range.max));
    play("tick", 0.4);
    buzz("tap");
  };
  const hold = useHold(raise);
  return (
    <div class="bw-bid" role="group" aria-label="Your bid">
      <Button id="bw-pass" variant="violet" onClick={props.onPass} disabled={props.busy}>
        Pass
      </Button>
      <button type="button" class="bw-bid-sign" id="bw-bid-sign" aria-label={`Bid ${amount}${amount > range.min ? `. Back to ${range.min}` : ""}`} onClick={() => props.setAmount(range.min)}>
        <span class="bw-bid-n">{amount}</span>
      </button>
      <button
        type="button"
        class="btn teal bw-raise"
        id="bw-raise"
        aria-label="Raise 5"
        disabled={props.busy || amount + range.step > range.max}
        {...hold}
        onClick={(e) => e.preventDefault()}
        onKeyDown={(e) => {
          if (e.key === "Enter" || e.key === " ") {
            e.preventDefault();
            raise();
          }
        }}
      >
        +{range.step}
      </button>
      <Button id="bw-bid" variant="ok" onClick={props.onBid} disabled={props.busy}>
        Bid
      </Button>
    </div>
  );
}

/** The nest: tap cards to put back, then Done once the count is right. */
export function NestBar(props: { need: number; chosen: number; onDone: () => void; busy: boolean }) {
  const left = props.need - props.chosen;
  return (
    <div class="bw-nest" role="group" aria-label="Put back cards">
      <p class="bw-cue-line outlined" aria-live="polite">
        {left > 0 ? `Put back ${left}` : left < 0 ? `${-left} too many` : "Ready"}
      </p>
      <Button id="bw-nest-done" variant="ok" disabled={left !== 0 || props.busy} onClick={props.onDone}>
        Done
      </Button>
    </div>
  );
}

/** Trump: four big suits, a ring on the one held most. Keys 1 to 4. */
export function TrumpPicker(props: { suggest: Suit | null; onPick: (suit: Suit) => void; busy: boolean; keys: boolean }) {
  return (
    <div class="bw-trumps" role="group" aria-label="Pick trump">
      {SUITS.map((suit, i) => (
        <button
          type="button"
          id={`bw-suit-${suit}`}
          class={`bw-suit ${suit} ${props.suggest === suit ? "hint" : ""}`}
          disabled={props.busy}
          onClick={() => props.onPick(suit)}
          aria-label={`${SUIT_NAME[suit]} trump`}
        >
          <SuitIcon suit={suit} />
          <span>{SUIT_NAME[suit]}</span>
          {props.keys ? <kbd aria-hidden="true">{i + 1}</kbd> : null}
        </button>
      ))}
    </div>
  );
}

/** 5 players: call a card you don't hold. Its holder is your secret partner. Trump's row first. */
export function PartnerPicker(props: { choices: CardId[]; trump: Suit | null; rules: RuleSetId; onPick: (card: CardId) => void; busy: boolean }) {
  const rows = partnerRows(props.choices, props.trump, props.rules);
  return (
    <div class="bw-partner panel" role="dialog" aria-label="Call a partner">
      <h2 class="outlined">Call a partner</h2>
      <div class="bw-partner-rows">
        {rows.map((row) => (
          <div class="bw-partner-row" role="group" aria-label={row.suit === props.trump ? `${SUIT_WORD[row.suit]}, trump` : SUIT_WORD[row.suit]}>
            {row.cards.map((c) => (
              <button type="button" class="bw-mini" disabled={props.busy} aria-label={cardLabel(c, props.rules)} onClick={() => props.onPick(c)}>
                <BirdFace id={c} rules={props.rules} />
              </button>
            ))}
          </div>
        ))}
      </div>
    </div>
  );
}

/** Between hands (§5.4): the bid, made or missed, each side's points this hand and its total. */
export function HandSummaryCard(props: { room: RoomView }) {
  const s = lastHand(props.room);
  if (!s) return null;
  const v = props.room.birdwatch!;
  return (
    <div class="bw-summary" role="status" aria-live="polite">
      <div class="panel bw-summary-card">
        <h2 class="outlined title">
          {seatName(props.room.seats[s.bidder])} bid {s.bid}
        </h2>
        <p class={`bw-made ${s.made ? "made" : "missed"}`}>{s.made ? "Made it" : "Missed"}</p>
        <ul>
          {s.rows.map((r) => (
            <li class={r.bidding ? "bidding" : ""} style={{ ["--ribbon" as string]: r.ribbon ?? "transparent" }}>
              <span class="who">{r.name}</span>
              <span class={`pts ${r.change < 0 ? "minus" : ""}`}>{signed(r.change)}</span>
              <span class="total">{r.total}</span>
            </li>
          ))}
        </ul>
        {v.status === "playing" ? <p class="fine">Next hand soon</p> : null}
      </div>
    </div>
  );
}

/** The score sheet: every hand so far, a column per side. */
export function ScoreSheet(props: { room: RoomView; onClose: () => void }) {
  const v = props.room.birdwatch!;
  const names = v.teams.map((t) => sideName(props.room, t));
  return (
    <Sheet title="Score sheet" onClose={props.onClose}>
      <div class="bw-sheet-scroll">
        <table class="bw-sheet">
          <thead>
            <tr>
              <th scope="col">Hand</th>
              <th scope="col">Bid</th>
              {names.map((n) => (
                <th scope="col">{n}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {v.history.map((r) => (
              <tr>
                <th scope="row">{r.hand}</th>
                <td>
                  <span class="bw-sheet-bid">
                    {seatName(props.room.seats[r.bidder])} {r.bid} <SuitIcon suit={r.trump} size={18} /> {r.made ? "" : "Missed"}
                  </span>
                </td>
                {r.change.map((c, t) => (
                  <td>
                    <span class={c < 0 ? "minus" : ""}>{signed(c)}</span> <strong>{r.totals[t]}</strong>
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr>
              <th scope="row" colSpan={2}>
                To {v.target}
              </th>
              {v.scores.map((n) => (
                <td>
                  <strong>{n}</strong>
                </td>
              ))}
            </tr>
          </tfoot>
        </table>
        {v.history.length === 0 ? <p class="fine">No hands yet</p> : null}
      </div>
    </Sheet>
  );
}

/** The bid's state on this device: the amount on the sign, starting at the least it may be. */
export function useBidAmount(range: { min: number } | undefined, key: string) {
  const [amount, setAmount] = useState(range?.min ?? 0);
  useEffect(() => {
    if (range) setAmount(range.min);
  }, [key, range?.min]);
  return [Math.max(amount, range?.min ?? 0), setAmount] as const;
}
