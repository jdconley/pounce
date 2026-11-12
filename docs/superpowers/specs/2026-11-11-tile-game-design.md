# Pounce tile game (working title "Tuna Tiles"): design

Date: 2026-11-11 · Owner: JD Conley (Conley Chaos LLC) · Status: draft for approval · Lives in `github.com/jdconley/pounce`

Parent specs: `2026-10-31-pounce-cat-tower-design.md` (product principles, architecture), `2026-10-31-pounce-ios-design.md` (art direction, table, pass-and-play, forfeit), `2026-11-04-daily-habit-design.md` (streaks, notifications, minors). Where this document is silent, they apply.

Marks: **(JD)** = decided by JD in the brief for this work. **(call)** = builder call made while writing this, open to override. **(built)** = in the rules module that ships with this spec (`apps/play-api/src/tiles`, `src/games/tiles.ts`, `src/bots/house-cat-tiles.ts`).

## 1. What this is and why

Pounce's second game. It is tile rummy, a traditional game family. Players empty a rack of numbered pieces by laying them on a shared table in runs and groups, and may rearrange everything already on the table to make room. The mechanics are the traditional ones. The name, theme, pieces, art and every word of the rules below are ours. **(JD)**

Cat Tower is a race you run side by side. This game is a shared puzzle. Every piece on the table belongs to everyone, and the fun is seeing a move nobody else saw. That makes it a good second game for the same couple and the same family table.

**Success:** JD and family play it on their phones, mixing shared-phone, own-phone and remote seats in one game, a turn takes under a minute to compose, and nobody submits a table the server refuses.

## 2. Goals, non-goals, anti-goals

**Goals**
- The rules in §4, enforced on the server, with hidden racks and a hidden pool. **(JD)**
- One submission per turn, because play is asynchronous over hours or days. **(JD)**
- 2 to 4 seats, any mix of shared phone, own phone, remote and House Cat. **(JD)**
- A phone UI that makes a big table and a 14+ piece rack workable with one thumb (§5).
- A simplified mode for players under 13, and for anyone who wants it (§5.10).
- Streaks, turn reminders, nudges, retiring a stalled seat and forfeit work as they do in Cat Tower (§6).

**Non-goals (this PR)** **(JD)**
- Registering the game with rooms, any change to `room/core.ts`, `protocol.ts`, the HTTP layer, notifications or `apps/play-ios`. The module ships with nothing calling it. §9 proposes the wiring.
- Art, sounds, the iOS scene.

**Anti-goals**
- Anything that reads as a commercial tile game: its name, its tile face, its wild character, its colours or its rulebook wording. Not in code, comments, tests, docs, UI copy or commit messages. **(JD)**
- A turn you have to submit piece by piece, or a table you place freehand on a canvas.
- Any view or event that carries another rack or the pool's order.
- Suits you can only tell apart by colour.
- Chat. **(JD)**

## 3. Theme and pieces

### 3.1 The idea **(call)**

The cats have emptied the toy box onto the rug and are tidying up. The pieces are cat toys, the table is the rug from Cat Tower, the pool is the toy box, and a rack is that cat's stash. A move tidies toys into rows.

| Rules word (code) | What players see |
| --- | --- |
| piece (`tile`) | a toy token |
| suit | the kind of toy |
| wild | Yarn, as in Cat Tower |
| rack | your stash |
| pool | the toy box |
| table | the rug |
| run | a row |
| group | a match |

### 3.2 Suits **(call, in the brand palette JD gave)**

| Suit (code) | Toy | Colour | Silhouette | Texture band |
| --- | --- | --- | --- | --- |
| `fish` | toy fish | teal `00D1C1` | fish, tail right | scallop scales |
| `mouse` | toy mouse | violet `7B2FFF` | round mouse, long curled tail | dots |
| `feather` | feather wand | orange `FF8A00` | one curved feather | diagonal stripes |
| `bell` | jingle bell | yellow `FFD21F` | round bell with a slot | horizontal bands |
| Yarn (wild) | ball of yarn | magenta `FF2E9A` | the Cat Tower yarn ball | none: it sparkles |

A suit is carried three ways, so colour is never the only one: the silhouette, the texture band and a corner pip in the silhouette's shape. Colour-blind players read the silhouette. Players reading a small table read the texture.

### 3.3 Piece design direction **(call)**

Style D "Loud Toy" from the iOS spec: glossy, chunky, thick dark outlines.

- A piece is a rounded token with a saturated body in its suit colour. The numeral is white with the app's thick dark outline, top centre and as large as the token allows. The silhouette sits under it. The texture band runs along the bottom edge. This is the opposite of a pale tile with coloured ink.
- Numerals stay readable at 30 pt wide, the size a piece has on a full table (§5.7). The style checkpoint must show the numeral 13 on yellow and on teal at that size before art production starts.
- The two copies of a piece look identical.
- Yarn is the magenta yarn ball already drawn for Cat Tower, on a white token so it never passes for a suit. In a set it shows a small ghost of the piece it stands for (the numeral in a run, the missing suit's pip in a match).
- The toy box is a chunky open box with a count badge. Rack backs, for other seats and the pass curtain, are violet with the paw, like Cat Tower's card back.
- VoiceOver labels: "7, fish", "Yarn, wild, standing for 6 mouse", "Row, fish, 4 to 7", "Match, nines, three toys".

### 3.4 Name candidates **(call)**

"Tuna Tiles" is the working title and the code id is `tiles`, which never changes. Five better names, best first:

1. **Tidy Paws.** Says what you do: tidy toys into rows. Warm, and it sits well next to Cat Tower.
2. **Toy Stash.** The rack is a stash and the goal is to empty it.
3. **Rug Rows.** Plain and literal. The rug is already the table in every Pounce game.
4. **Nine Lines.** A pun on nine lives, with rows as lines. Clever, a little cold.
5. **Stash Dash.** Carries the race to empty your stash. Sounds faster than the game is.

None of these has had a trademark or App Store search. That has to happen before one is chosen.

## 4. Rules, in our words

Rules aren't copyrightable. The wording below is ours and is what the in-app help should be written from. **(JD)**

### 4.1 Pieces and deal **(JD, built)**

106 pieces: the numbers 1 to 13 in four suits, two of every piece, and 2 Yarn. Each player is dealt 14 onto their rack. The rest is the pool, face down. Who moves first is picked at random by the game's seed **(call)**, because seats keep their order across "Play again" and a fixed first seat would always favour the host.

### 4.2 Sets **(JD, built)**

Everything on the table sits in a set of three or more pieces.

- **A run** is three or more pieces of one suit with numbers that climb by one: 4, 5, 6. A 1 is only ever low, and nothing comes after 13. A run can be as long as 13 pieces.
- **A group** is three or four pieces of one number, every one a different suit.

### 4.3 A turn **(JD, built)**

A turn is one submission. Pick one:

- **Play.** Put one or more pieces from your rack onto the table. You submit the whole table as it should stand when you are done. It is legal when every set on it is a run or a group, every piece that was on the table is still on it, and everything new came from your rack. Nothing goes back to a rack.
- **Draw.** Take the next piece from the pool. That is the whole turn.
- **Pass.** Only when the pool is empty.

You may draw, or pass on an empty pool, even when you could play.

### 4.4 The opening **(JD, built)**

Your first play has to stand on its own. Until you have opened, a play may only add new sets built entirely from your rack, those sets must be worth 30 or more, and every set already on the table must be left exactly as it is. Add up the number on each piece. Once you have opened you may take the whole table apart and rebuild it, as long as it ends the turn as valid sets with at least one of your pieces added.

Sets already on the table count for nothing toward the 30, and you cannot add to one on your opening turn. **(call, the plain reading of the rule)**

### 4.5 Yarn **(JD, built; details are calls)**

A Yarn stands for any one piece.

- In a run it is the number its place gives it: in 4, Yarn, 6 it is the 5, and in 4, 5, Yarn it is the 6. It can't be a 0 or a 14.
- In a group it is the group's number in a suit that isn't there yet.
- It counts as the piece it stands for toward the opening 30.
- Once on the table it stays on the table. A player who has opened may move it to any set, like any other piece. Nobody takes it back to a rack. **(JD: simplified for a phone)**
- One number piece with both Yarn can be read two ways: 5, Yarn, Yarn is the run 5, 6, 7 and also a group of 5s. It counts as whichever is worth more, and as a run on a tie. **(call)** Yarn, Yarn, 10 is therefore a group worth exactly 30, and it opens.

### 4.6 The end and the score **(JD, built; the blocked score and shared wins are calls)**

- The first player to empty their rack wins. The game ends there.
- If the pool is empty and every player still in passes in a row, nobody can move. The game ends and the lowest rack total wins. Equal lowest totals share the win.
- A rack total is the numbers on its pieces added up, and 30 for each Yarn.
- Score: everyone is charged their own rack total. Each winner also collects the totals of the players who did not win. Going out, the winner's own total is 0, so this is the usual rule. In a blocked game the winner scores the others' totals less their own. In a shared win each winner collects the full amount, so nothing is split into fractions. A winner always has the best score at the table.
- One round is one game.

### 4.7 Edge cases, builder calls **(call, built)**

- A run must be submitted in climbing order, because that order is how a Yarn says which number it is. A group may be in any order.
- The order of the sets on the table carries no meaning in the rules. The server keeps the order of the last submission, so everyone sees the same layout.
- "Left exactly as it is" means the same pieces in the same order. Before opening you may list the existing sets in a different order, but not reorder the pieces inside one.
- A play resets the passes. Passes only count once the pool is empty.
- The game can't run forever. Draws are limited by the pool, plays by the 106 pieces, and passes end the game once everyone has made one in a row.
- Nobody's leftover rack is ever shown, even after the game. Only the totals are.

### 4.8 Forfeit **(JD: like Cat Tower's; where the pieces go is a call, built)**

Any player may forfeit until the game is over, on anyone's turn. Bots never do. Retiring a stalled seat (Cat Tower spec §3.3) is a forfeit on that seat's behalf.

- **One other player left:** the game ends and that player wins, `reason: "forfeit"`. Nobody scores, because nobody went out.
- **Two or more left:** the seat is out and finishes last. It is never given a turn again and can't win. A forfeit on the seat's own turn passes the move on. On someone else's turn the move stays put. It is not a turn for streaks.
- **Its rack leaves play.** The pieces are set aside face down (`boxed` in the state) for the rest of the game. They are not returned to the pool and they count for nobody at the end. The pieces the seat already played stay on the table for everyone.

Why set aside and not back in the pool:

1. It is what Cat Tower does with a forfeited hand, so the two games explain forfeit the same way.
2. It reveals nothing. Putting pieces back would tell the leaver exactly what the pool now holds, which matters on a family table where they may still be in the room.
3. It never lengthens a game that just lost a player. A refilled pool means up to 14 or more extra draws.
4. No set on the table can be broken by it, since table pieces are untouched.

The cost is that some pieces can no longer turn up, so a set someone was waiting on may never complete. That is acceptable, because every player is equally in the dark about which pieces left.

If the forfeit leaves only players who have all passed since the last play, the game ends as blocked right then.

## 5. Composing a turn on a phone

This is the hard part. A late-game table can hold 25 sets and 80 pieces, the rack can hold 20 or more, the screen is 393 pt wide, and the whole turn is one submission.

### 5.1 Principles **(call)**

1. **The turn is a draft.** Nothing is sent until Play. Every drag changes a local copy of the table and rack. The server never sees a half-built turn.
2. **The app lays out the table, the player doesn't.** Sets flow in rows like words in a paragraph. There is no freehand canvas, no pieces left lying loose, and no pixel positions on the wire. The server holds an ordered list of sets.
3. **Big targets.** You never have to hit a 30 pt piece. You aim a rack piece at a whole set, and you open a set before picking a piece out of it.
4. **The app checks the rules before the server does.** The Play button only lights when the draft passes the same checks as `checkPlay`. Shared vectors (`apps/play-api/fixtures/tiles-sets.json`) keep the Swift port honest, as `groups.json` does for Cat Tower.

### 5.2 Layout, top to bottom (portrait)

1. **Opponents bar**, as in Cat Tower: each other seat's cat in a ring, a count bubble for pieces on the rack, presence pose, badges for House Cat, not yet opened (a closed toy box) and passed. The seat to move pulses.
2. **The rug:** the table of sets. The toy box sits in its top right corner with the pool count.
3. **The action strip:** Undo, Reset, the turn button, the opening meter (before you open), sort and tidy toggles.
4. **Your stash:** the rack. Two rows of seven at 48 pt wide, which is exactly the deal. A third row appears at 15 pieces. Past 21 the rack scrolls sideways by row.

### 5.3 The rack

- **Sorting:** two toggles, by number (1s together, then 2s) and by toy (each suit in order). Sorting by number makes groups visible, by toy makes runs visible. A third tap returns to free order. Drag to reorder freely at any time. The order is saved per table on the device.
- **Ready sets:** in either sorted view, pieces that already form a set sit a hair closer together with a shared underline. No words.
- **A new piece** from a draw lands at the right end with a flip, then joins the sort on the next toggle.
- **Multi-select:** tap pieces to lift several, then drag any one of them to move them together. Lifting three that form a set and dropping them on empty rug makes that set in one move.

### 5.4 Building and rearranging

Every action has a drag path and a tap path (select, then tap the target), as the iOS spec requires.

- **Rack to rug, new set:** drag onto empty rug, or onto the "new row" slot at the end of the table. One piece alone makes a set of one, which shows as unfinished (§5.5).
- **Rack to an existing set:** drag onto the set. The whole set is the target. The app puts the piece where it belongs. A run sorts itself by number, and a group has no order. If the piece fits nowhere in that set it still lands, and the set shows as broken, so a player can build toward a rearrangement in any order.
- **Yarn:** dropped on a run it fills the gap if there is one. With no gap it takes the end nearer the drop. Its ghost numeral shows what it stands for at once.
- **Table to table (after opening):** tap a set to open it in the **loupe**. The set grows in place to rack size and the rest of the rug dims. Drag a piece out of the loupe to any other set or to empty rug, or tap the piece and then the target. Drag the loupe's own handle to move the whole set onto another, which joins them.
- **Splitting a run:** in the loupe, tap the gap between two pieces. The run breaks there into two sets.
- **Rack pieces back:** a piece you placed this turn has a small paw dot. Drag it back to the rack, or tap it twice. A piece that was on the table at the start of the turn can't be dropped on the rack: it snaps back with the "nope" wiggle.
- **Before opening** the existing sets wear a thin lock ring and don't open in the loupe. Trying shakes the opening meter instead, which is the explanation.

Untouched sets must be submitted exactly as the snapshot gave them, piece for piece. The client keeps each set's server order and only re-sorts a set the player has changed.

### 5.5 Validity feedback before submit

Each set in the draft is in one of three states, shown by shape as well as colour:

- **Fine and unchanged:** plain.
- **Fine and changed this turn:** a solid glow and a small check paw.
- **Not a set yet:** a dashed outline that breathes, with one glyph for why: a "3" for too short, two different silhouettes for mixed suits in a run, a doubled silhouette for a suit twice in a group, a broken chain for a gap.

**The turn button** is the only way a turn is sent, and it is always one of four things:

| Draft | Button |
| --- | --- |
| nothing moved, pool has pieces | **Draw** (the toy box) |
| nothing moved, pool empty | **Pass** (a sleeping paw) |
| pieces placed, every check passes | **Play** (the big paw, pulsing) |
| pieces placed, something is wrong | greyed, and tapping it scrolls to the first set that isn't one |

**The opening meter** shows until you open: a toy box filling toward 30 with the running total of your new sets. It turns gold at 30. Only valid new sets count, so the number never promises more than the server will accept.

Draw and Pass end the turn, so each takes a press and hold of about 0.4 s, like the pass curtain. If the draft has pieces placed, the button is Play or greyed, so a player can't draw by accident mid-build. Reset first.

If the server still refuses a play (a bug, or a stale draft), the app maps the error to the same visuals (`bad_set` and `table_touched` to the set states, `opening_too_low` to the meter), keeps the draft and never shows a code.

### 5.6 Undo and reset

- **Undo** steps back one drop, as far as the start of the turn. A multi-piece move is one step.
- **Reset** returns the table and rack to the snapshot. Press and hold, since it throws away work.
- The draft is saved on the device, keyed by table code and the view's `turns` counter, so leaving the app mid-build loses nothing. Nobody else can change the table while you hold the move, so a saved draft can't go stale. If `turns` has moved on (the seat was retired), the draft is dropped.

### 5.7 A big table

- **Fit by default.** Sets wrap into rows. Pieces are 30 pt wide when the table is small and shrink to no less than 24 pt as it grows. The longest run, 13 pieces, fits one row at 27 pt, so a table holding one is drawn at 27 pt or smaller. Past what fits, the rug scrolls vertically.
- **Pinch** zooms from fit up to rack size. Double tap toggles between fit and rack size around the tap.
- **While dragging** a rack piece over the rug, the set under the finger swells to rack size and its neighbours slide aside, so the target is always large. Holding near the top or bottom edge scrolls.
- **Tidy** (a toggle) orders the sets: runs by toy then number, then groups by number. It is how the draft is listed in the submission, so everyone sees the tidy table afterwards. Off, sets keep their places and new sets go at the end.
- **What changed:** when you open a table that others played on while you were away, the pieces placed since your last turn carry the placing cat's ring colour for a few seconds, played back in turn order from the `played` events. Tap the "what changed" paw to see it again. With no events to hand (a cold start), the app compares against its cached last-seen table and highlights without colours.

### 5.8 What the other players see

Each submission arrives as one `played` event with the new table and the pieces placed. Other phones animate the placed pieces flying from that cat to their sets and the rest of the table sliding to its new shape. A draw shows a piece going from the toy box to that cat, face down. Nobody sees a draft in progress.

### 5.9 Pass-and-play privacy

The Cat Tower curtain rules apply (iOS spec §5.9), with one difference: the table is public, so the curtain covers the rack and action strip, and the rug stays visible above it.

- A phone with one seat never sees a curtain.
- A phone with two or more seats shows the curtain over the rack whenever the move comes to one of its seats that isn't the one revealed. Press and hold to reveal. Rack nodes for unrevealed seats are never created.
- A turn ends on Play, Draw or Pass, and the rack hides the moment it does. After a draw the new piece shows for a beat with "hold to continue", so the drawer sees it before the phone moves on.
- A draft only ever exists for the seat holding the move, and it is sent or reset before the rack hides, so no draft outlives its owner's turn on screen.
- Off turn, tapping one of your local cats and holding peeks at that rack. Release hides it.

### 5.10 Kittens (under 13) and easy mode **(call)**

The under-13 limits in the daily habit spec §14.1 apply unchanged: generated names, no server pushes, no chat, nothing new collected. On top of that the tile game has an **easy mode**. It is on by default for the kitten age band, and anyone can turn it on from the table menu. It changes the app only. The rules and the server are the same, so a kitten and a grandparent can share a table.

- **Add-only by default.** Build new sets from the rack and add pieces to sets on the rug. The loupe, splitting and joining are behind a "tricks" paw the player can turn on when ready. The game is fully playable without them.
- **Show me.** A hint paw lights the next thing to do: three rack pieces that make a set, or a piece and the set it fits. It runs on the device with the same greedy finder as the House Cat, so nothing is sent or logged.
- **The rack sorts itself** and ready sets are pulled together.
- **Pieces snap to where they fit.** A piece dropped on a set it can't join goes back to the rack with the "nope" wiggle instead of leaving a broken set.
- **The opening is a picture:** the toy box meter is larger, and the pieces that count hop into it.
- **Nothing fits?** The turn button itself says Draw with a gentle pulse once the hint finder comes up empty.
- No timers anywhere, and no penalty for using hints.

### 5.11 Accessibility

As the iOS spec §13: every action has a tap path, VoiceOver reads sets and pieces (§3.3) and offers custom actions ("Add to row, fish 4 to 7", "Start a new set", "Take back"), Reduce Motion swaps flights for fades, touch targets are 44 pt or more through the swell and the loupe, and state is never carried by hue alone.

## 6. Streaks, reminders and nudges

- **`endsTurn` (built):** true for a play, a draw and a pass. Each is a whole turn ended by the seat's own action, which is the daily habit spec's definition (§6.1). False for a forfeit, though it moves the turn on.
- **Streaks:** a turn at a shared table counts exactly as in Cat Tower. A draw counts. That is deliberate. Drawing is often the right move, and the late move pass (§6.1 there) exists so nobody loses a day for lack of a move.
- **"Your move" pushes, the local reminder, nudges, retiring a stalled seat:** unchanged. They key off the `turn` event and `currentActor`, which this module provides. Kitten and teen limits apply as they do now.
- **More turns per game than Cat Tower.** Every turn hands the move on, including a one-tap draw. The existing push backoff and quiet hours cover this, but see open question 1.
- **Live table (Live Activity):** shows each seat's phase today. For this game it should show pieces left on each rack. That needs the change in §9.

## 7. The House Cat **(built)**

`chooseAction(view, seat, rng)` in `src/bots/house-cat-tiles.ts`. It reads only its own seat's view, so it can't cheat. It always returns a legal action.

- **Before opening:** find sets in the rack, runs first and groups first, and keep the better. If they are worth 30, lay them all down. If not, spend a Yarn on a pair that needs one more, then stretch a set with a Yarn, and open if that reaches 30. Otherwise draw. It never touches the table.
- **After opening:** lay down every set in the rack, spend a Yarn on a pair, then fit single pieces onto the table: the end of a set, a long run split around a twin, the place of a Yarn that then moves to another set. Then borrow a spare table piece (the end of a run of four or more, any piece of a group of four) to finish a pair from the rack. Last, try taking the whole table apart and rebuilding it with the rack mixed in, and keep whichever plan leaves the fewest pieces.
- **Yarn:** a spare one is held back until it is the last piece or the pool is empty.
- **Nothing to put down:** draw, or pass once the pool is empty.
- It is greedy throughout. It does not search rearrangements, so a patient person will find moves it misses. The `rng` only breaks ties.
- **Speed:** about 0.36 ms a move across the soak test's 23,680 moves, with the slowest single move at 15 ms on a laptop, against a budget of 50 ms. The largest rack a game can hold (53 pieces) is tested on its own.

The room's "plain legal move" fallback for a rejected bot action is a draw, or a pass when the pool is empty.

## 8. The module, as built

`src/games/tiles.ts` exports `tiles: GameModule<TilesState, TilesAction, TilesView, TilesEvent, TilesError>`, id `tiles`, 2 to 4 seats. Pure and deterministic: `create(seats, seed)` shuffles with the existing `createRng` and `shuffle`, deals, and picks the first seat. Nothing after the deal is random, so the state does not keep the seed.

```ts
type TilesAction =
  | { type: "draw" }
  | { type: "play"; table: TileId[][] }   // the whole table after the turn
  | { type: "pass" }
  | { type: "forfeit" };

type TilesView = {
  status: "playing" | "gameOver"; turn: Seat; turns: number;
  table: TileId[][]; poolCount: number; rackCounts: number[];
  racks: Record<Seat, TileId[]>;          // only the seats this device controls
  opened: boolean[]; passed: boolean[]; forfeited: boolean[];
  winners: Seat[]; scores: number[]; endReason?: "out" | "blocked" | "forfeit";
};

type TilesEvent =
  | { kind: "drew"; seat: Seat; tile?: TileId; poolCount: number }  // tile: the drawer only
  | { kind: "played"; seat: Seat; table: TileId[][]; placed: TileId[]; opened: boolean }
  | { kind: "passed"; seat: Seat }
  | { kind: "turn"; seat: Seat }
  | { kind: "forfeited"; seat: Seat }
  | { kind: "gameOver"; winners: Seat[]; reason: EndReason; scores: number[]; left: number[] };
```

Piece ids are 0 to 105. 0 to 103 are numbers: suit `floor(id / 26)` in the order fish, mouse, feather, bell, and number `(id % 13) + 1`. 104 and 105 are Yarn.

Errors, in the order a play is checked: `game_over`, `not_your_turn`, `bad_piece` (malformed table), `duplicate_piece`, `missing_piece` (a table piece is gone), `not_your_piece`, `nothing_played`, `bad_set`, `table_touched` and `opening_too_low` (before opening). Also `pool_empty` (draw), `pool_not_empty` (pass), `bad_seat` and `forfeited` (forfeit), `bad_action`.

Hidden information: a view holds the table, the counts and the controlled racks. The pool's order, the set-aside pieces and every other rack never leave the server, during the game or after it. The only private event field is the drawn piece.

`checkPlay(table, rack, opened, submitted)` is exported so a bot, a hint or a test can ask whether a play is legal without a state.

## 9. Making rooms and the protocol multi-game (proposal, not in this PR)

Today rooms are hard-wired to Cat Tower in more places than the type parameter: `room/core.ts` reads `CatTowerState` fields directly, `protocol.ts` parses Cat Tower actions, and the app decodes one `GameView`. The plan below is additive, keeps version 1.0 of the app working untouched, and can ship behind a flag.

### 9.1 `games/module.ts`: what a room needs that it reads from Cat Tower today

Add to `GameModule`, with Cat Tower's implementations moved out of `core.ts` and `protocol.ts`:

| New member | Replaces | Tiles |
| --- | --- | --- |
| `parseAction(raw: unknown): A \| null` | `parseAction` in `protocol.ts` | object with a known `type`; `table` at most 35 sets and 106 ids |
| `phase(s): "playing" \| "between" \| "over"` | `game.status` reads in `liveAfterGame`, `afterGameChange`, `retire` | never `between` |
| `betweenAction: A \| null` | the room's `{ type: "nextRound" }` on a timer | `null` |
| `forfeitAction: A`, `forfeited(s): boolean[]` | `{ type: "forfeit" }` in `retire`, `game.forfeited` in `outPlayers`, `allOut`, `game-room.ts` | as built |
| `turnKey(s): string` | `${game.round}:${game.turn}` in `turnKey()` | `${s.turns}` |
| `startsTurn(e: E): boolean` | `event.kind === "turn" \|\| "roundStarted"` in `applyGame` | `e.kind === "turn"` |
| `fallbackAction(s, seat): A` | `fallbackAction` in `core.ts` | draw, or pass |
| `progress(s): number[]` and a `progressKind` | `game.phase` in `liveView` | pieces left per seat |

Add `games/index.ts` with `GAMES = { "cat-tower": catTower, tiles }` and `type GameId = keyof typeof GAMES`.

### 9.2 `room/core.ts`

- `RoomState.game: GameId` (today the literal `"cat-tower"`). Every stored room already has `game: "cat-tower"`, so there is no migration.
- `gameState` becomes the module's state type. `RoomCore` takes its module from `GAMES[state.game]` in place of the `catTower` default parameter, and every `as CatTowerState` cast goes away with the members above.
- `RoomCore.create(..., game: GameId = "cat-tower")`. `LOBBY_SEATS` (6) becomes `module.maxSeats`, so a tiles lobby has 4 seats. `start` already checks `minSeats`.
- "Play again" copies `game` to the new table.
- `room/tables.ts`: `TableEntry.game?: GameId` and a `game` column, so Home can show the right art per table.
- `live/live.ts`: `LiveSeat.phase` becomes a `progress` number plus the kind, so the Live Activity can show a shelf or a piece count.

### 9.3 `protocol.ts`

- **Creating:** `POST /v1/rooms` already takes `game`. It accepts any id in `GAMES` that the `GAMES` env flag turns on (the same pattern as `STREAKS`, `LINK` and `NUDGE`).
- **Old apps must never land in a room they can't draw.** Version 1.0 decodes `room.game` strictly as a Cat Tower view. The app says which games it can play in a header on the socket upgrade, `X-Pounce-Games: cat-tower,tiles`. No header means `cat-tower`. For a room whose game isn't listed the Worker answers 404, which the 1.0 app already treats as a table that doesn't exist. The `/j/<CODE>` page for such a room says the table needs the newest Pounce.
- **One key per game, no polymorphic decoding.** `RoomView.game` stays Cat Tower's view and is `null` in other games. Add `RoomView.gameId: GameId` and `RoomView.tiles?: TilesView`. `RoomEvent` gains `{ kind: "tiles"; event: TilesEvent }` beside `{ kind: "game"; event: GameEvent }`. This matters because the two games share event names (`drew`, `turn`, `forfeited`, `gameOver`) with different payloads, and a Swift `Codable` enum can't choose by a sibling field without custom context.
- **Actions:** `ClientMessage.act.action` is validated by `parseClientMessage` only as a JSON object, then by the room through `module.parseAction`. `MAX_MESSAGE_BYTES` (8192) is enough, since a full 106-piece table is under 1 KB.
- **Errors:** `ErrorCode` gains `TilesError`. It reuses `not_your_turn`, `forfeited`, `bad_seat` and `game_over`, which already exist.
- `PROTOCOL_VERSION` stays 1. Everything is additive.
- **Fixtures:** `fixtures/protocol/` gains tiles snapshots and events for the Swift tests, beside `fixtures/tiles-sets.json`, which this PR adds.

### 9.4 iOS client (`apps/play-ios`)

- `Protocol/Models.swift`: `RoomView` gains `gameId: String?` (nil reads as Cat Tower) and `tiles: TilesView?`. `GameView` keeps its wire shape.
- `Protocol/Messages.swift`: `Action` stays Cat Tower's. Add `TilesAction` and `ClientMessage.actTiles(seat:action:id:)`, which encodes the same `{"t":"act"}` envelope. `GameEvent.swift`: `RoomEvent` gains `.tiles(TilesEvent)`. Unknown kinds are already dropped.
- `Net/APIClient.swift`: `createRoom(game:)` (today it sends the literal `"cat-tower"`), and the socket upgrade sends `X-Pounce-Games`.
- `TilesRules.swift`: a port of `readSet` and `checkPlay`, tested against `fixtures/tiles-sets.json`, to drive §5.5.
- A `TilesTableModel` and `TilesScene` beside the Cat Tower ones, chosen by `gameId`. The draft model of §5 lives in `TilesTableModel`.
- Home: a game picker on Play, and per-table art from the tables list's `game`.
- Widgets and the Live Activity: read `progress` and its kind.

### 9.5 Order of work

1. Server: the module members and `GAMES`, with Cat Tower behaviour unchanged and its tests green. No wire change.
2. Server: the wire additions behind the `GAMES` flag and the header gate.
3. iOS: rules port and protocol types, then the scene, then the picker.
4. Turn the flag on once a build with the game is in TestFlight.

## 10. Testing **(built)**

Vitest, beside the code, 100% statement and branch coverage of `src/tiles/**` enforced in `vitest.config.ts`, as for `src/rules/**`.

- **Sets:** shared vectors, Yarn in every position of runs and groups, both Yarn in every pair of positions, the two-way readings, 1 and 13 as edges.
- **Opening:** exactly 30, 29, a Yarn's value by position, sets already on the table, every way of touching the table before opening.
- **Plays:** every error with its cause, and which error wins when several apply. Rearranging after opening: split, borrow, move a Yarn, a Yarn that can't leave.
- **Turns:** draw, pass, turn order, going out, the blocked ending, ties, scoring.
- **Forfeit:** two seats and more, on and off turn, the set-aside pieces, forfeits during the passing round.
- **Views and events:** no other rack and no pool piece, with a helper that fails on any field it hasn't been told about.
- **Conservation:** all 106 pieces are in exactly one place after every action.
- **House Cat:** each behaviour in §7, and every action accepted by the engine.
- **Soak** (`tests/tiles-sim.test.ts`): 300 seeded bot-only games, 100 each at 2, 3 and 4 seats. Every action accepted, every invariant above checked after every action, every game finished. Result: 79 turns a game on average (102, 77 and 58 for 2, 3 and 4 seats), longest 132, 56% of turns draws, 299 won by going out and 1 blocked.

## 11. Open questions for JD

1. **Is the game too long for play over days?** Bot games run about 100 turns at two seats, 50 each, and 56% of all turns are draws. People rearrange better than the House Cat and will finish sooner, but this is still several times a Cat Tower hand. Options if a playtest agrees: a short game (one copy of each piece, 54 pieces, deal 10), or leave it. The engine would need the set size and deal as parameters. Nothing is built for this.
2. **Scoring a blocked game and a shared win** (§4.6). I chose "winner collects the others' totals less their own" and "each winner collects in full". Scores are also shown once and recorded nowhere. Do they need to exist beyond the standings?
3. **A forfeited rack leaves play** (§4.8), not back to the pool. Agree?
4. **A draw or a pass counts as a streak turn** (§6). Agree, or should only a play count?
5. **First player is random per game**, not the host (§4.1). Agree?
6. **One piece with two Yarn reads as whichever is worth more** (§4.5). The alternative is to make the player say which, which is more interface for a rare case.
7. **Wire shape** (§9.3): a key per game and a 404 for apps that don't list the game, or a protocol version 2. I recommend the first.
8. **"What changed since my turn"** (§5.7) leans on events the app may have missed. Should the view carry the last move of each seat?
9. **The name** (§3.4), after a trademark and App Store search.
