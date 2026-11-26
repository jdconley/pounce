# Birdwatch server: the wire, for the iOS, TV and web sessions

As built on `claude/birdwatch-server-9114b9` (PR #156), from commit 4ea9ece0 on. Plan with every ruling:
`docs/superpowers/plans/2026-11-25-birdwatch-server.md`. Samples to decode, made from real rooms:
`apps/play-api/fixtures/protocol/birdwatch-server-messages.json` (19 snapshots, every event, every new
error) and `birdwatch-client-messages.json`. Types: `apps/play-api/src/birdwatch/{engine,view}.ts`,
`src/protocol.ts`.

## Getting in

- Flag: `GAMES` lists `birdwatch` in `.dev.vars.example` and tests only. Production stays `"tiles"`.
- Header: a 1.3 app sends `x-pounce-games: cat-tower,tiles,birdwatch` on every request and socket.
  Without it: create is 400, the socket upgrade 404 (426 with `x-pounce-app`), lists leave it out.
- Create: `POST /v1/rooms {"game":"birdwatch"}`. The lobby has 6 seats, 4 open, 2 closed, and
  `options: {"rules":"official"}`. Start needs 4 to 6 seats filled (`not_enough_players`).

## Cards and suits

- `CardId` 0-56. Suited: suit `floor(id / 14)` in order fish, mouse, feather, bell; rank `id % 14 + 1`.
  56 is the Bird. Suits on the wire are the strings `"fish" | "mouse" | "feather" | "bell"`.
- Rank order: 2 up to 14, then 1 on top (1s exist only in tucker and friesen).
- Counters: 5 = 5, 10 and 14 = 10, 1 = 15, Bird = 20. Every hand is 120 (official) or 180.
- Clients never port the rules: dim and enable from `playable`, `bidRange`, `partnerChoices`.

## Lobby messages (host only, lobby only; else `not_allowed` / `not_lobby`)

```json
{"t":"setOptions","options":{"rules":"official"|"tucker"|"friesen"}}
{"t":"swapSeats","seats":[a,b]}          // bad_seat for the same seat or out of range
```

Teams follow seat order after start compacts the seats: 4 players `[[0,2],[1,3]]`, 6 `[[0,3],[1,4],[2,5]]`,
5 players one side per seat.

## Snapshot

`room.gameId: "birdwatch"`, `room.game: null`, `room.options: {rules}`, `room.birdwatch: BirdView` once
dealt. A seat a House Cat took over: `{"kind":"bot","person":{...the person who left},"yours":false,"presence":null,"left":true}`.

```ts
type BirdView = {
  rules: "official" | "tucker" | "friesen"; seats: number; target: number; minBid: number; maxBid: number;
  nestSize: number; teams: Seat[][]; scores: number[] /* per team */; history: HandResult[];
  status: "playing" | "over"; phase: "bidding" | "nest" | "trump" | "partner" | "play" | "between" | "over";
  hand: number /* 1-based */; dealer: Seat; turn: Seat | null /* null between hands and once over */;
  handCounts: number[]; hands: Record<Seat, CardId[]> /* only this device's seats */;
  bids: (number | null)[]; passed: boolean[]; high: { seat: Seat; amount: number } | null /* after bidding: the hand's bid */;
  trump: Suit | null; called: CardId | null /* 5p: the called card, public */; partner: Seat | null /* 5p: set once the called card is played, or at hand end */;
  trick: { seat: Seat; card: CardId }[]; leader: Seat | null; lastTrick: { cards: { seat; card }[]; winner: Seat } | null;
  played: CardId[] /* this hand, in order */; points: number[]; tricks: number[] /* per seat, this hand */;
  winners: Seat[];
  // Only for the device that may use them:
  playable?: CardId[];                                   // play phase, this device holds the seat on the move
  bidRange?: { min: number; max: number; step: number }; // bidding, this device holds the seat on the move (pass is always allowed)
  fromNest?: CardId[];                                   // nest phase, bid winner's device: the cards that came from the nest (glow them)
  putBack?: CardId[];                                    // bid winner's device after the nest; everyone once the hand is scored
  partnerChoices?: CardId[];                             // partner phase, bid winner's device: every deck card it doesn't hold
  youArePartner?: Seat;                                  // 5p: the seat this device holds that has the called card (show the mark behind the curtain)
  endReason?: "target" | "left";
};
type HandResult = { hand; bidder: Seat; bid: number; partner: Seat | null /* 5p only; null = alone */; trump: Suit;
  made: boolean; taken: number[]; change: number[]; totals: number[] /* all per team */ };
```

A TV (screen) controls no seat, so its view never has `hands`, `youArePartner` or any choice field.

## Actions: `{"t":"act","seat":n,"action":…,"id"?:…}`

```json
{"type":"bid","amount":85}          // multiple of 5, >= bidRange.min, <= maxBid
{"type":"pass"}
{"type":"nest","discard":[…nestSize ids]}
{"type":"trump","suit":"bell"}
{"type":"partner","card":56}        // 5 players only
{"type":"play","card":13}
{"type":"forfeit"}                  // leave: a House Cat takes the seat
```

`nextHand` exists but only the room sends it, about 6 s after a hand ends (`between`).

## Events: `{"t":"event","seq":n,"event":{"kind":"birdwatch","event":E}}`

```ts
| { kind: "dealt"; hand; dealer; handCounts: number[]; hands: Record<Seat, CardId[]> /* this device's seats only */ }
| { kind: "bid"; seat; amount } | { kind: "passed"; seat } | { kind: "bidWon"; seat; amount }
| { kind: "nest"; seat; cards?: CardId[] /* bid winner's device only */ }
| { kind: "putBack"; seat; count; cards?: CardId[] /* bid winner's device only */ }
| { kind: "trump"; seat; suit } | { kind: "called"; seat; card }
| { kind: "turn"; seat }            // after every action that leaves someone to act
| { kind: "played"; seat; card }
| { kind: "partner"; seat }         // 5p: the called card was just played
| { kind: "trick"; winner; cards: { seat; card }[]; points }
| { kind: "handOver"; result: HandResult; putBack: CardId[] }
| { kind: "gameOver"; winners: Seat[]; scores: number[]; reason: "target" | "left" }
```

Room event, outside the game's kind: `{"kind":"houseCat","seat":n}`, when a seat's person leaves
(their forfeit, or retired after 3 days). The game plays on and ends (`reason: "left"`) once no person
is left. The seat keeps the leaver's `person` for its name tag, and no device controls it. On the
leaver's Home the table shows as over and is never their turn. Deleting or merging their account
reaches that seat too.

## Errors (new)

`wrong_phase`, `bid_too_low`, `bid_too_high`, `bad_bid`, `bad_card`, `not_your_card`, `wrong_count`,
`duplicate_card`, `own_card`, `must_follow`. Reused: `not_your_turn`, `bad_action`, `bad_seat`,
`game_over`, `not_allowed`, `not_lobby`, `not_enough_players`, `game_off`.

## Live table

`progressKind: "score"`, `progress` per seat = its side's score (teammates match; 5p each its own).

## For the web session

`apps/play-web/tests/catalog.test.ts` lists `birdwatch` in `NOT_YET` (server games the web doesn't
draw). Remove it when the web table lands. `gameOf` in `src/ui/tv/tv-model.ts` narrows the id with a cast.
