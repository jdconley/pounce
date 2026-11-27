# Toy Tumble: design

Date: 2026-11-26 · Owner: JD Conley (Conley Chaos LLC) · Status: approved by the lead on 2026-11-26, with House Cat levels added (§6.9) · Release: switched on for the web player and the web TV page once every client's code is merged and cross-play passes; the iPhone, iPad and Apple TV app gets it in 1.4 (§10) · Lives in `github.com/jdconley/pounce`

Parent specs: `2026-10-31-pounce-cat-tower-design.md` (product principles, architecture), `2026-10-31-pounce-ios-design.md` (art direction), `2026-11-11-tile-game-design.md` (rooms with more than one game, the `GAMES` flag), `2026-11-15-web-player-design.md`, `2026-11-16-tv-table-design.md`, `2026-11-25-birdwatch-design.md`. Where this document says nothing, those apply.

Marks:
- **(JD)** means JD decided it.
- **(lead)** means the manager session decided it, as JD's appointed lead ("use good judgement and be the lead").
- **(call)** means a builder call made while writing this, open to override.

## 1. What this is and why

Toy Tumble is Pounce's first real-time game. Everyone plays at once, each on their own phone. Toys fall into a toy box, and you clear full rows. Clearing rows hurts everyone else, and tricks you pick up let you hit a chosen player or save yourself. The TV, or the web TV page, shows every box live. It works in one room and across the internet. **(JD)**

JD's reason, in his words: "the back and forth and fun nature of it. being able to adversely effect someone then coming back from near defeat." He loved a 1990s online falling-blocks battle game (called "the old battle game" below) and Dr. Mario. He wants "buffs and debuffs and ways to affect other players" on a falling-blocks base. **(JD)**

Two things carry that feeling, and both are protected throughout this design:
1. **Back and forth.** Attacks can be blocked and sent back (§4.5). Nobody can only take hits.
2. **Comebacks.** A box near the top gets better tricks (§4.6). Two tricks can turn a round around in one move (Swap, Bath).

**Success:**
- JD's family plays a game of Toy Tumble on phones and the TV, with one player remote on ordinary internet.
- Nobody notices lag on their own box.
- Every round has a moment where somebody yells.
- A kid playing against parents wins rounds.

## 2. Goals, non-goals, anti-goals

**Goals**
- 2 to 6 players, free for all. **(call)**
- The host can seat House Cats at two levels, Easy and Quick, in any seat but the last human one. A kid can play alone, and two siblings get a real match. **(lead)**
- Each player's own box runs on their own device. Moves never wait on the network. It renders at 60 fps or better, and at 120 Hz on screens that can (§7).
- Play in one room, remotely, or both at once, at one table. The TV is optional: phones show every opponent as a mini box. **(JD)**
- iPhone, iPad, the web player (touch and keyboard), the Apple TV table and the web TV page, all at one table, with the same rules.
- Remote players on ordinary home or mobile internet feel the game is fair (§6.7).

**Non-goals (first release)** **(call)**
- Teams. The rules leave room for them later: junk could go to the other team only.
- A single-player or daily mode. Playing against House Cats covers practice.
- Playing on the Siri Remote or a game controller. The Apple TV shows the table; phones play.
- Two players on one shared phone. In Toy Tumble each human seat is its own device.
- Playing by turns over hours, "your move" pushes, the Lock Screen live table. A round needs everyone at once.
- Hold, combo chains, spin bonuses, ranked play, replays, chat.
- Phone landscape. The game follows whatever the app's game screens already allow.

**Anti-goals**
- **Anything that reads as the classic falling-blocks game or the old battle game:** their 10 by 20 well, their seven pieces in their colors, their brick look or their junk-line look (§3). Their names, and the trade words for their pieces, appear nowhere: not in code, comments, tests, docs (this one included), UI copy or commit messages. A words test enforces it (§9.2). Code says toy, box, row, junk and trick.
- **Input lag** on your own box, from any cause.
- **A dropped frame** while playing.
- **A pile-on with no way out:** a kid knocked out in 20 seconds every round, with nothing to do about it.
- **Screens full of words.** The game teaches with tips (§5.8).

## 3. Making it ours (legal)

The idea of falling pieces that clear full rows is a game mechanic, and anyone may use it. The expression is not free to copy. In the Xio Interactive case (D.N.J. 2012, 863 F. Supp. 2d 394), the court found a clone infringing because it copied the look:
- the 10 by 20 playing field,
- the seven pieces drawn as bricks in bright distinct colors,
- the junk lines' appearance,
- the ghost piece,
- the next-piece display,
- pieces changing color as they lock.

The classic game's owner enforces its marks and trade dress actively. So every visible element below differs from the classic game on purpose. The reason for each is recorded here. **(lead: board and pieces as proposed; legal reasoning kept in the spec)**

| Element | Classic game | Toy Tumble | Why it's ours |
| --- | --- | --- | --- |
| Playing field | 10 by 20 well, 1:2 | a toy box 12 columns by 18 rows, 2:3, with a cat peeking over the rim **(JD)** | different dimensions and proportions, a themed container instead of a bare well, a character that reacts |
| Piece set | seven 4-cell pieces | nine toys: two 3-cell, five 4-cell with no zigzags, and two 5-cell (a plus-shaped paw print and a U-shaped food bowl) **(JD)** | a different number and mix of shapes. The 5-cell toys only fit a wider box. |
| Piece look | flat or beveled bricks, one solid color per piece | round plush cushions, each stitched with a toy silhouette, in the Tuna Tiles toy colors (fish, mouse, feather, bell) **(JD)** | a different surface, a different palette, and silhouettes that carry meaning |
| Colors per shape | long one cyan, square yellow, T purple, L orange, J blue | 4 toy colors across 9 shapes. The long 4-cell toy is never cyan, the square is never yellow, and the T is never purple. **(call)** | no shape-to-color mapping can echo theirs |
| Junk | gray lines with a hole | gray fluffy hairball rows with one gap, drawn as fur, not blocks **(JD)** | a different look for the same idea |
| Landing preview | a ghost of the piece | a dashed paw-print outline where the toy will land **(call)** | a different mark |
| Next piece | a box at the side with the next pieces | the next toy only, sitting on the cat's paw at the rim **(call)** | a different place and presentation |
| Clearing rows | the row flashes and vanishes | the cushions pop like stuffing and the cat bats the fluff away **(call)** | our own animation |
| Losing | the stack fills, "game over" | the cat tips the box over, and toys spill **(JD)** | our own ending |
| Rotation | the classic rotation system and its kick tables | our own pivots and a short list of nudges (§4.2) **(call)** | none of their tables are used |
| Name and words | their marks | Toy Tumble, toys, the box, rows, hairballs, tricks | §3.1 |

Specials (the old battle game's letter blocks) become **tricks** with cat names and effects of our own mix (§4.6).

**Review.** No outside counsel review gates the build. **(call: a family app, every element above differs, and the riskiest two, the landing preview and the next toy, are restyled and moved)** Instead, the style checkpoint (§11) puts the finished look next to the classic game's and checks it row by row against this table. A row that looks close is redrawn before production art. If the manager or JD wants counsel to look, the checkpoint images are the thing to send.

### 3.1 Name **(lead)**

**Toy Tumble.** The code id is `tumble` and never changes, even if the display name does.

A search on 2026-11-26, of US records via Trademarkia (`trademarkia.com/search/trademarks?query=toy%20tumble`, plus a wildcard `toy tumble*`), found no TOY TUMBLE mark, live or dead.
- The nearest live marks are TUMBLE, owned by Clarified Inc. (serials 90470980, 90977163, 97981778 and 90869383). Their class 9 goods are downloadable apps for laundry services and for running washing machines. They are not games, and "Toy Tumble" as a whole differs. This is the same kind of unrelated class 9 hit Birdwatch accepted (§3.4 of its spec).
- No live TUMBLE or TOY TUMBLE mark was found in class 28 (games and toys) or class 41 (entertainment).
- Trademarkia's search is fuzzy. Confirm on USPTO TSDR before any filing.

Names considered and dropped:
- **HAIRBALL:** a live HAIRBALL mark in class 41 (serial 87750573, live music performances) and live HAIRBALL AUDIO marks in class 9 (serials 87041527 and 87041546).
- **TUMBLE BOX:** the same TUMBLE marks as above, with nothing to set it apart.

The game is named inside Pounce, not as its own App Store app.

## 4. Rules, in our words

The engine implements this section exactly, in TypeScript (server, web, web TV page) and Swift (iPhone, iPad, Apple TV), with shared fixtures (§9). How to play is written from it.

### 4.1 The box and the toys

- **The box** is 12 columns (x 0 to 11, left to right) by 18 rows (y 0 to 17, bottom to top). Above it are 4 hidden rows, y 18 to 21, where toys appear.
- **The toys.** Each one is a set of cells. Code names are shapes, not brands: **(call)**

  | id | Cells | Shape |
  | --- | --- | --- |
  | `i3` | 3 | short stick |
  | `v3` | 3 | corner |
  | `i4` | 4 | long stick |
  | `o4` | 4 | square |
  | `t4` | 4 | T |
  | `l4` | 4 | L |
  | `j4` | 4 | mirrored L |
  | `p5` | 5 | plus (the paw print) |
  | `u5` | 5 | U (the food bowl) |

- **The queue.** Toys come in bags. Every bag shuffles the seven 3- and 4-cell toys. Every other bag also holds a 5-cell toy, so bags run 8, 7, 8, 7: `p5` in bags 0, 4, 8 and so on, `u5` in bags 2, 6 and so on. **(tuned by the soak, §9.3)**
  - The first design put a 5-cell toy in every bag.
  - In the soak, a 5-cell toy made a new hole 55 to 60% of the times it was placed, against 16% for the small toys. That is 3.4 times as often, past the 15% line the plan set for an unfair dead end. Halving how often they come keeps the paw print and the bowl in the game without making them the thing that ends it.
- **Same toys for everyone.** Every box in a round gets the same queue, from the round's seed. **(call: fairness, and a race to read the same toys is part of the fun)**
- **A new toy** appears centered (rounding left) with its lowest cells in row 18. If it overlaps anything, that box is **out**.

### 4.2 Moving, turning, dropping

- A toy moves left or right one column at a time, and soft-drops one row at a time. It can't overlap cells or leave the box's sides or floor.
- **Turning** rotates a quarter turn around the toy's pivot:
  - `o4` doesn't turn.
  - `i3`, `i4`, `p5` and `u5` turn around the center of their bounding box, rounded toward the bottom-left.
  - The other toys turn around the cell at their corner or center.
  - The exact pivot table is the engine's and the fixtures' to fix. **(call)**
- **Nudges.** If a turn overlaps, the engine tries shifting the turned toy, in this order: (0,0), (-1,0), (+1,0), (0,+1), (-2,0), (+2,0). The first one that fits wins. If none fits, the turn doesn't happen. **(call: our own short list)**
- **Falling.** The toy falls one row every `g` ms. `g` starts at 1000 ms, gets 15% faster every 30 seconds of the round, and never goes below 50 ms. After 2:30 the **Zoomies** start: it gets 30% faster every 15 seconds. **(call)**
- **Setting down.** A toy that can't fall further sets down 500 ms later. Moving or turning resets that wait, up to 15 times per toy. A drop sets it down at once.

### 4.3 Clearing rows

- A row with all 12 cells full is cleared. The rows above it move down.
- Clearing at once sends junk (§4.5):

  | Rows cleared | Junk sent |
  | --- | --- |
  | 1 | 0 |
  | 2 | 1 |
  | 3 | 2 |
  | 4 | 4 |

  No toy is taller than 4, so 4 is the most.

### 4.4 Out, rounds and winning **(call)**

- A box is **out** when any cell is left above row 17. That can follow a set-down after its clears, junk or a trick. A new toy that can't appear needs such a cell, so the same rule covers it. Its cat tips the box over. An out player watches the rest of the round.
- **A round ends** when one box is left, or when no person's box is left.
  - The last box standing wins the round.
  - If only House Cats are left, the one that has cleared the most rows wins.
  - If the last boxes go out within the same 100 ms on the server, nobody wins, and the next round starts.
- **The game is first to 3 round wins.** Then the usual Game over and Play again.
- Between rounds, the standings show for 5 seconds, then a 3-2-1 countdown starts the next round.
- Rounds are short: usually 1 to 3 minutes, and the Zoomies end any round soon after 2:30.

### 4.5 Junk and blocking it **(JD: the back-and-forth)**

- **Junk goes to every other box still in the round**, in the amount of §4.3. This is the old battle game's way: it's simple and loud. **(call; tune it after playtests, for example by spreading it across opponents)**
- **Incoming junk waits** in a meter beside the box for 2 seconds, counted on the receiving device from when it arrives. A box can have several waiting.
- **Blocking.** Each row of junk a box would send cancels one waiting row first, oldest first. Only what's left over goes out to the others. So a player under attack clears rows to block it, and a big clear blocks and hits back at once.
- **Landing.** Waiting junk whose 2 seconds are up lands when the box next sets down a toy that clears nothing. It lands as rows pushed in under the stack. All rows from one attack share one gap column, so a good drop clears them all.
- Junk sent to a box that's out is dropped.

### 4.6 Tricks **(JD: buffs and debuffs)**

- **Where they come from.** Each row you clear adds one trick to your box. It sits as a glowing badge on a random cell that's already filled (not the falling toy).
- **Pocketing.** Clear the row a trick sits on and you pocket it. You can hold up to 6. A 7th is lost. Tricks still on cells move with the stack, junk included. Bath and Swap take them along.
- **Using one.** Pick a trick you hold, then pick any box still in the round, your own included. Tricks may be used in any order. **(call: kids pick what they can see; the old battle game's use-the-first-one rule is harder to explain)**

| Trick (UI word) | Does | Default target in the UI |
| --- | --- | --- |
| Hairball | adds 1 junk row at once, with a random gap. It doesn't wait and can't be blocked. | opponents |
| Paw Swipe | shoves each row 0, 1 or 2 cells left or right at random, wrapping around | opponents |
| Catnip | toys fall 4 times as fast (never faster than 50 ms) for 10 seconds | opponents |
| Scoop | clears the bottom 2 rows. Their tricks are pocketed if it's your own box. | yourself |
| Settle | every cell falls straight down to fill gaps below it, then full rows clear. It sends no junk. | yourself |
| Nap | no tricks or junk reach this box for 10 seconds. Anything sent is lost. | yourself |
| Swap | trades box contents with the target: cells and the tricks on them. Neither held tricks nor falling toys move. | opponents |
| Bath | wipes the box empty | yourself |

- A trick used on a napping box is spent and does nothing. The napping box shows a sleepy "zz" puff. The exception is the box's own Scoop, Settle, Nap or Bath used on itself: those still work. **(call)**
- Swap needs another box. Aimed at your own box it is refused, and you keep it. **(call)**
- **Waiting junk** belongs to the player, not the box's contents. **(call: so the save tricks really save)**
  - Bath wipes the box and clears its waiting junk too.
  - Swap leaves each player's waiting junk with that player.
  - Scoop, Settle, Hairball and Paw Swipe don't touch it.
- **Rows a trick removes are not clears.** **(call)**
  - Rows removed by Scoop, or completed and removed by Settle, send no junk, block no waiting junk and add no new tricks.
  - Tricks sitting on those rows are pocketed by that box's player, up to the limit of 6.
  - Tricks on a box that Bath wipes are lost.
  - The rows that Hairball and Paw Swipe change are never cleared by the trick itself. Any full row is cleared at the next set-down, as usual.
- **How often each trick appears**, by weight: Hairball 20, Paw Swipe 15, Scoop 18, Catnip 12, Settle 12, Nap 10, Swap 3, Bath 3. **(call)**
- **Comebacks.** While a box's highest cell is in row 12 or above (the top third), its new tricks use Swap ×3, Bath ×3 and Scoop ×2. **(JD: "coming back from near defeat"; the call is the numbers)**
- Every random choice in a trick's effect (gaps, shoves) is made by the server and carried in the hit (§6.4). Where tricks land on cells is decided by each box's own seeded generator (§6.2).

## 5. The table on a phone, the web and the TV

### 5.1 Lobby and starting **(call)**

- The host picks Toy Tumble on the shelf. Seats: 2 to 6, House Cats allowed. A device holds at most one seat in Toy Tumble.
- Invites work as for every game, so remote players join by link or code.
- **Start** lights when every human seat's device is connected. Until then it reads "Waiting for Sam" (or "Waiting for 2").
- There are no "your move" pushes and no Lock Screen live table. Invites and Play again pushes work as usual.
- **Later rounds** start by themselves only while every remaining human seat's device is connected.
  - When someone is missing, the countdown waits and the standings read "Waiting for Sam".
  - After 20 seconds of waiting, the host gets "Play without Sam". That seat then sits out rounds, shown as Away, until its device is back. It rejoins at the next countdown.
  - With no human device connected, the game waits between rounds with nothing running. The room sleeps, no House Cat plays, and the table stays on Home until someone comes back.
  - So a family that puts the phones down never has its game finished by cats. **(call)**
- **Leaving for good** (Leave, or forfeit) takes that seat out for the rest of the game. No House Cat takes it over. **(call: a real-time seat has no turn for a cat to inherit)**
  - Its wins stay on the standings.
  - The game ends early when fewer than 2 seats are left, or no human seat is left. The seat left with the most wins wins.
- **No turns.** Turn reminders, nudges, stalling and retiring don't apply: nobody is ever "to act".
  - The module reports `currentActor` as null throughout.
  - The room runs Toy Tumble's rounds itself (§6).
  - `forfeitAction` is the Leave above.
  - Each round a human seat plays counts as that player's turn for streaks.
- Home's table card shows "Round 2" and the leader's wins while a game is on.

### 5.2 The phone, portrait

```
 +-------------------------------+
 | [cat+next toy]   1 2 [wins]   |   rim: your cat holds the next toy
 | +---------------+  +--+ +--+  |
 | |               |  |  | |  |  |   mini boxes: every opponent, live,
 | |   your box    |  +--+ +--+  |   with cat face and wins.
 | |   12 x 18     |  +--+ +--+  |   They are also the targets for tricks.
 | |               |  |  | |  |  |
 | |               |  +--+ +--+  |
 | |               |  [junk meter]
 | +---------------+             |
 | [trick][trick][trick]  ...    |   tricks you hold, up to 6
 +-------------------------------+
```

- **Your box** takes most of the screen and leans left, so the right thumb's drags don't cover it. Cells are 20 pt or more on an iPhone SE.
- **Mini boxes** for up to 5 opponents sit in a column, or a 2-column grid when needed, on the right. Each has the cat's face, a wins count and a junk meter.
  - At a TV table (`room.screen`), the minis shrink to chips: cat face, name, a stack-height bar and wins. The TV shows the boxes. **(call)**
- **The trick tray** sits along the bottom. Tap a trick to lift it. The default targets glow. Tap a mini box, or your own box, to use it. Dragging the trick onto a box works too. Tap the lifted trick again to put it down.
- **Your junk meter** is a column of hairballs against your box's right edge. Each one shrinks as its 2 seconds run out.
- **Hits** show on both ends:
  - the thrower's cat winds up on the minis,
  - something flies to the target,
  - the target's box shakes,
  - and it gets a haptic.
- **Out:** your box tips over. The screen switches to watching: every box big, in a grid.
- **iPad:** the same layout, larger. In landscape, the minis split to both sides of your box.

### 5.3 Touch controls **(call)**

They are designed for zero lag and no aiming:
- **Drag** left or right anywhere on your box. The toy moves one column for every cell-width the finger travels. The finger doesn't need to be on the toy.
- **Tap** turns clockwise.
- **Drag down** soft-drops for as long as you hold.
- **Flick down** drops. A flick is a fast downward swipe, past a velocity threshold the builder tunes.
- Input is applied when the touch event arrives and shows on the next frame. No input waits for a frame or the network.
- Haptics: light on setting down, medium on a clear, strong on a hit.
- The game area turns off the system's swipe-back.

### 5.4 Keyboard (web) **(call)**

| Key | Does |
| --- | --- |
| Left and right arrows | move, with repeat after 150 ms, then every 33 ms |
| Down arrow | soft drop |
| Up arrow or X | turn clockwise |
| Z | turn counter-clockwise |
| Space | drop |
| 1 to 6 | use the first trick you hold on the player with that number. Each mini box shows its number, and yours shows too. |

Touch on the web works as in §5.3.

### 5.5 Between rounds and the end

- **Round over** shows for 5 seconds: the winner's cat on top of its box with confetti, and paw tokens for everyone's wins.
- Then the 3-2-1 countdown on every screen.
- **Game over** is the shared Game over screen, with Play again.

### 5.6 The TV table (Apple TV and the web TV page) **(call)**

```
 +-----------------------------------------------------------------+
 |  Toy Tumble                Round 2                 code ABCDEF  |
 |  +-----+  +-----+  +-----+  +-----+  +-----+  +-----+            |
 |  |     |  |     |  |     |  |     |  |     |  |     |            |
 |  | box |  | box |  | box |  | box |  | box |  | box |            |
 |  |     |  |     |  |     |  |     |  |     |  |     |            |
 |  +-----+  +-----+  +-----+  +-----+  +-----+  +-----+            |
 |  cat Sam  cat Mia  ...      (name, wins, tricks held, junk meter) |
 +-----------------------------------------------------------------+
```

- Up to 6 boxes in one row, sized to fill the screen. With 2 to 4 players they're bigger.
- Hits fly across the TV from thrower to target.
- KOs tip the box. The round winner gets the big moment.
- Falling toys move smoothly. The TV animates each toy's fall between position updates (§6.3).
- A TV can join mid-round and shows every box at once (§6.6).

### 5.7 Web player

- It's the same game in the web player, drawn on a canvas, with touch and keyboard.
- The TV page draws the TV table.
- Both follow the web player's layout and art rules.

### 5.8 Teaching

Tips follow the tip system, one at a time, each shown when it matters and never again once learned:
1. "Drag to move."
2. "Tap to turn."
3. "Flick down to drop."
4. When the first trick is pocketed: "Tap a trick, then a box."
5. When junk first waits: "Clear rows to block it."

How to play gets a Toy Tumble page with the tricks table, and a video later. UI words are short: Round 2, Out, Waiting for Sam, Reconnecting, You win the round. The trick names are the UI words of §4.6.

### 5.9 Sound

- Short sounds for:
  - a toy setting down,
  - a clear (a purr that grows with the rows cleared),
  - a hit (by trick),
  - the meter running out,
  - the box tipping,
  - the round win.
- Everything respects the sound setting.

## 6. Real time: who decides what, and the wire

### 6.1 The model **(call: approach B in §8)**

**Each device runs its own box, and the server referees.**

- Every box is a deterministic engine fed by one ordered stream of events: toys set down, junk landing, tricks used on it.
- The device playing a box writes that box's stream.
  - It moves and drops the toy locally with no network in the loop.
  - It sends each event as it happens.
- The server runs the same engine for every box. It checks each event, and only then relays it with a sequence number to every other device and screen at the table. Each of them replays it.
- The server owns the round:
  - who's out,
  - the clock,
  - the randomness in hits,
  - what junk and tricks are owed to whom,
  - and the winner.
- When the server refuses an event, it sends that device the box as the server has it, and the device snaps to it. Nobody else ever saw the refused event.

That gives:
- zero input lag on your own box;
- a single truth for what's on every box, which the TV and opponents see;
- cheating limited to what the referee lets through (§6.8).

### 6.2 Seeds and determinism

- At each round start, the room's state gives:
  - the round number;
  - the round seed, which fixes the toy queue for every box;
  - a per-seat trick seed, which fixes where that box's tricks land on cells;
  - the moment the round starts.
- The engine has no other randomness. Given a box's stream, every client and the server compute the same cells, tricks, clears and junk.
- It uses the existing xoshiro128** (`rules/rng.ts`), ported to Swift bit for bit.

### 6.3 Client to server

All messages are JSON, as the rest of the wire is. They're compact arrays like Purrtrait's ink. One message type carries a batch of events in order:

```json
{ "t": "tumble", "r": 2, "ev": [ ["m", 14, 1, 5, 9], ["l", 14, 1, 5, 3, 41250, [7]] ] }
```

`r` is the round. Events:

| Event | Meaning |
| --- | --- |
| `["m", n, rot, x, y]` | toy `n` of the queue is at this rotation and position. Only the latest goes in a batch. |
| `["l", n, rot, x, y, ms, landed]` | toy `n` set down here at `ms` on the device's round clock. `landed` lists the junk ids that landed after it (§4.5), oldest first. |
| `["a", id]` | the device applied hit `id` (a trick) or started the 2-second wait for junk `id` |
| `["u", slot, seat]` | use the trick in this slot on `seat` |

- **Sending:** at most one batch every 50 ms while something changes, and at once on a set-down or a trick. Nothing is sent while the toy is still and nothing happens.
- **The exact shape is checked.** Anything else is `bad_message`. A message stays under the protocol's 8 KB limit.
- **Rate limit:** at most 30 batches per second per device. A device over it gets a sync (§6.6), not silently dropped events, since dropped events would split the box.

### 6.4 Server to everyone

- **A box's checked events,** relayed to every other connected device and screen at the table:

  ```json
  { "t": "tumble", "r": 2, "s": 1, "q": 88, "ev": [ ... ] }
  ```

  - `s` is the seat and `q` the per-box sequence number.
  - `m` events are relayed at most every 66 ms per box (about 15 a second). The latest wins.
  - A device that sees a gap in `q` asks for a sync.
- **A hit** goes to everyone, so every replayer applies it in the target's order:

  ```json
  { "t": "tumbleHit", "r": 2, "id": 31, "from": 0, "to": 1, "k": "junk", "x": { "rows": 2, "gap": 7 } }
  ```

  - Kinds and payloads:
    - `junk`: rows and gap.
    - `hairball`: gap.
    - `swipe`: one shift per row, -2 to 2.
    - `catnip`, `scoop`, `settle`, `nap`, `bath`: no payload.
    - `swap`: both boxes' cells and tricks, as the server last had them.
  - The target applies it the moment it arrives and sends `["a", id]`. Junk instead starts waiting (§4.5).
  - Every other replayer applies it to the target's box when the target's `a` event comes through. So every copy of a box applies hits in exactly the order the box's own device did.
  - A swap is the one hit with two targets. It goes to both, and each applies its half when acknowledging.
- **Round state** (round number, seeds, start time, who's out, wins, the winner) goes in the room snapshot, with a `seq`, like every other game's state.

### 6.5 What the server checks on each event

- `n` is the next toy in that box's queue.
- A set-down fits (no overlap, inside the box) and rests: it can't move down one row.
- The device acknowledges each hit within 3 seconds.
- Junk acknowledged more than 4 seconds ago, by the server's clock, has landed or been blocked by the box's next set-down.
- A trick used is one the box holds, on a box still in the round.
- Events arrive in a sane order, and set-down times only go forward.
- A box with no set-down for 25 seconds has its owed junk landed by the server. That is longer than the slowest real fall: 18 rows at 1000 ms, plus the set-down wait. Without it, a connected device that stops setting down could never lose. **(call, found building House Cats)**

Not checked, on purpose **(call)**:
- whether the toy could actually have been steered to where it set down;
- whether the player is humanly fast.

A family game doesn't need either, and both are costly to check.

On a failed check, or a hit not acknowledged in time:
- The server applies its own view (the hit, the junk).
- It sends that device `{ "t": "tumbleSync", "r", "boxes": [{ seat, ... }] }` with the full box. The device snaps to it.

### 6.6 Joining, dropping and coming back

`tumbleSync` carries the whole state of one or more boxes:
- cells and the tricks on them,
- queue position,
- held tricks,
- waiting junk with the time left,
- active Catnip or Nap with the time left,
- the `q` reached.

When it goes out:
- **A TV or phone that connects mid-round** gets a sync of every box, then the live stream.
- **A phone that drops** (no messages for 3 seconds):
  - Its box shows "Reconnecting" everywhere, and its toy hangs still.
  - Junk and tricks aimed at it wait.
  - Back within 15 seconds: it gets a sync of its own box and every other box. The toy in hand restarts at the top, and play goes on.
  - After 15 seconds: the box is out for this round, the cat tips it, and the player is back next round.
- **The app going to the background** (a call, the home screen) counts as a drop. There's no pause.
- **A server restart mid-round** (a deploy, an eviction):
  - The round lives in memory and is lost.
  - The room replays that round from a new countdown, and the wins so far stand. Wins and round results are stored at each round's end.
  - Deploys are rare, rounds are short, and this keeps the server simple. **(call)**

### 6.7 Feeling fair over real networks **(call)**

- Your own box never touches the network.
- What travels:
  - Junk and tricks reach their target one trip later: thrower to server to target, typically 50 to 200 ms.
  - Junk then waits 2 seconds anyway, so latency barely matters for it.
  - Tricks are felt within a fifth of a second, about as fast as anyone can see the throw.
- The TV and minis show boxes about one trip behind. Falling toys are animated between updates, so they glide rather than jump.
- The room's Durable Object sits near whoever created the table. A remote cousin far away has a longer trip, and only their hits arrive later.
- **Targets**, measured over real networks (§9.5):
  - Hit delivery p95 under 250 ms between two US home or mobile connections.
  - TV lag p95 under 200 ms in the same house.

### 6.8 Anti-cheat, proportionate **(call)**

This is a family game. The checks in §6.5 stop:
- floating or overlapping toys,
- picked toys,
- invented or hoarded tricks,
- ignored junk,
- flooding.

A modified client could still play faster or smarter than a person. That's accepted. There are no rankings to protect.

### 6.9 House Cats **(lead: in v1, optional, two levels; details are calls)**

House Cats are opponents a kid can play alone against, or that turn two siblings into a real match.

- **Seating.** They're seated only on purpose, by the host in the lobby, as in every Pounce game. They never take over a seat that leaves (§5.1).
- **On the server.** They run in the room, with the same engine. They write the same event stream a phone does (§6.3), through the same checks, so the TV and observers need nothing new. They send junk and use tricks on the same rules as people.
- **Two levels**, chosen per table in the lobby with two pills, as Birdwatch's rule set is. The lobby shows "Cats: Easy" or "Cats: Quick". The game's option is `cats: "easy" | "quick"`, and the default is `easy`.

  | | Easy | Quick |
  | --- | --- | --- |
  | Think time per toy | 3.0 to 4.6 s | 0.8 to 1.6 s |
  | Picks a worse placement | 50% of the time | 15% of the time |
  | Uses tricks | only Hairball, Paw Swipe, Scoop and Nap; the rest it holds | all of them |

  Both levels must be beatable by a child. The soak (§9.3) also plays each level against a scripted "kid" player (think 2.5 to 4 s, picks the worse placement half the time, no tricks), and tunes until the kid wins at least 1 round in 3 against one Easy cat.
  - At the first Easy settings (1.4 to 2.4 s, 35%) the kid won 4%.
  - At the values above it wins 37.6% of 1,000 rounds.
- **Placement.** It scores every placement of the current toy (every turn and column, about 48). The score is -0.51 × total column height, +0.76 × rows cleared, -0.36 × holes, and -0.18 × bumpiness. It never looks ahead to the next toy.
- **Gravity.** A cat's toy falls like anyone's (`tumble/clock.ts`). When the toy has had time to fall to where it would rest, plus the 500 ms set-down wait, the cat sets it down where it is, planned or not. So the Zoomies hurry cats into mistakes, and cat rounds end.
- **Tricks.** It uses one 1 to 3 seconds after pocketing it.
  - Harmful tricks go to the human with the most round wins, then the lowest stack.
  - Helpful ones go to itself.
  - It never uses Swap from a box lower than the target's.
- **Moving.** It moves its toy in visible steps, relayed about 5 times a second, so it looks alive on the TV, then drops.
- **A capped rate.** One timer per room drives every cat, at most 10 ticks a second. A tick does at most one decision per cat. The room never runs cats outside a round, or when no human device is connected (§5.1).
- **Server cost.** Estimated per room with 5 cats:
  - about 48 placements × 216 cells per decision, under 0.2 ms each, so a few ms of CPU per second of round;
  - about 5 position updates a second per cat, fanned out to each socket.

  The soak and a room benchmark measure the real numbers: CPU ms per second of round, and messages out per second, for 1 human with 5 cats, watched by a TV. They're recorded here. The budget is under 10 ms of CPU per second of round per room. **(call)**

### 6.10 A shared live layer with Purrtrait **(lead: agreed)**

Purrtrait's ink and Toy Tumble's stream need the same room machinery:
- in-memory relay, with no storage;
- a per-device rate limit;
- fan-out to chosen sockets;
- a catch-up message for a device that connects late;
- a request to the sender after the room loses its memory.

So one generic helper, `apps/play-api/src/room/live-relay.ts`, gives a game exactly that, with a per-game rate limit and fan-out. Each game keeps its own messages and checks.

- The manager has asked Purrtrait to build it.
- If it isn't on `main` when Toy Tumble's server work starts, Toy Tumble writes it, to that shape, in a file of its own. Purrtrait may then adopt it.
- Toy Tumble never edits Purrtrait's files, and the reverse holds too.
- Toy Tumble's own live code lives in `apps/play-api/src/tumble/` (engine, round, checks, House Cats). It is wired into `room/core.ts` and `room/game-room.ts` by small hooks keyed on the game, as Birdwatch did.
- Those two room files are shared. Whichever branch merges second rebases onto the other.

## 7. Performance on every client

- **The engine is small** (a 12 by 18 grid). One step (a move, a set-down with clears, a replayed event) costs well under 0.5 ms. So it runs on the UI thread as a "small state update" (AGENTS.md), with the frame budget still under 8.3 ms.
  - Measure it in the frame gates.
  - If a replayed sync ever costs more, move it off the main thread.
- **Sockets, decoding and storage** stay in each platform's IO layer, off the main thread, as today. Decoded events are handed to the main thread in batches.
- **iPhone and iPad:**
  - SpriteKit, as the other games use.
  - `preferredFramesPerSecond` is the screen's maximum (120 on ProMotion).
  - Gravity and timers come from the frame clock and are independent of frame rate.
  - Settled cells are cached into one texture per box, re-made only on a set-down or a hit. Only the falling toy and effects are live nodes.
  - Minis are drawn the same way.
- **Apple TV:** the same SpriteKit board code at TV scale.
- **Web:** canvas 2D with `requestAnimationFrame`. Settled cells live on an offscreen canvas per box. Input is handled on the event, before the next frame.
- **Gates:** the iOS frame-rate test and the web `e2e/main-thread.spec.ts` each get a Toy Tumble case, run with no frame over budget and no main-thread hang:
  - 60 seconds of scripted play on the player's device, against 5 House Cats, with hits;
  - a TV showing 6 boxes for 60 seconds.

## 8. Approaches considered (real time) **(call: B)**

| | Approach | Trade-offs |
| --- | --- | --- |
| A | **Server simulates every box; phones send inputs and predict.** | Strongest against cheating. But every move needs prediction and rollback when the server disagrees, the server ticks 6 boxes at 60 Hz in one Durable Object, and a remote player's box would correct itself visibly on a bad connection. Heavy for a family game. |
| **B** | **Each device runs its own box and writes its stream; the server replays and checks every event, owns hits, outs and the round (chosen).** | Zero input lag by construction. The server does work only per event, not per frame. One truth for observers. It needs the engine in TypeScript and Swift to agree exactly, which the shared fixtures guarantee (§9.1). Cheats left open are harmless here (§6.8). |
| C | **Devices run their boxes, and the server only relays.** | Simplest, but no referee: a box could claim anything, desyncs go unseen, and nobody decides outs fairly. |

## 9. Testing **(call)**

### 9.1 One engine, two languages

- `apps/play-api/fixtures/tumble/*.json` hold event streams and the exact expected box after each step. They cover:
  - the queue,
  - turns and nudges against walls and stacks,
  - clears,
  - junk blocking and landing,
  - every trick,
  - trick placement and pocketing,
  - outs.
- The TypeScript engine (vitest) and the Swift engine (PounceKit tests) replay every fixture and must match cell for cell.
- A property test generates random streams in TypeScript and writes new fixtures. The Swift test runs them all.

### 9.2 Server

- The message shape and every refusal in §6.5, each with its sync.
- Rate limits.
- Relay to every socket but the sender's.
- `q` order.
- Hits applied in the target's order by observers.
- Swap.
- Reconnect within and after 15 seconds.
- A TV joining mid-round.
- A round lost to a restart replays.
- The end of the round and of the game.
- House Cats finish rounds.
- Nothing about a round's live stream is stored. A test reads every stored key mid-round.
- **Words test:** fails if any Toy Tumble file contains a name or trade word in §2's anti-goal. That covers the server, web, Swift, fixtures, docs and How to play. The banned list lives in the test encoded (ROT13), so the test itself never spells the words. The session brief gives builders the list.

### 9.3 Bot soak

10,000 offline House Cat rounds (2 to 6 cats, both levels, plus the scripted kid of §6.9), checking the server cost of §6.9 and:
- every round ends, and within 5 minutes;
- how often a 5-cell toy can't be placed without a hole (unfair dead ends);
- how often each trick decides a round.

Tune the 5-cell rate and the trick weights from this. Record the numbers here.

**Results, 2026-11-26** (`pnpm --filter @pounce/play-api soak:tumble -- --rounds 2000`, after the tuning in §4.1 and §6.9):
- **Rounds:** p50 180 s, p95 211 s, max 221 s. None over 5 minutes, and none stopped by the cap. All-cat rounds run long, because good cats rarely top out before the Zoomies; rounds with people end sooner.
- **5-cell toys:** they make a new hole 60% of the times they're placed, against 16% for the others. They now come in every other bag (§4.1).
- **Tricks:** the share of rounds where a harmful trick hit the deciding box in its last 5 seconds was Hairball 4%, Paw Swipe 3%, Catnip 3% and Swap 0.1%. No trick decides rounds on its own, so the weights stand.
- **The kid:** wins 37.6% against one Easy cat (§6.9).
- **Cost:** 6 Quick cats, the busiest a room gets, cost 0.26 ms of CPU per second of round. With 1 phone and 1 TV connected, that's about 14 sends a second. The budget was 10 ms (§6.9).

### 9.4 Clients

- Rendering snapshot tests at the screen sizes AGENTS.md lists: iPhone SE, a large iPhone, iPad portrait and landscape, and the largest text size.
- The frame gates of §7.
- Touch gesture tests: drag, tap, soft drop, flick, a trick onto a box.
- Keyboard tests on the web.

### 9.5 Real networks

- A small load tool runs N clients against a deployed dev Worker and records:
  - round-trip time,
  - hit delivery (thrower's send to target's receive, on synced clocks),
  - TV lag.
- Run it from three places:
  1. this Mac on home internet;
  2. a GitHub Actions runner in another region;
  3. a phone on cellular, by hand, with the result read from the app's debug overlay.
- The numbers go in `docs/perf/toy-tumble-latency.md`, against the targets in §6.7.

### 9.6 Cross-play

One game with:
- an iPhone,
- the web player,
- the Apple TV,
- the web TV page,
- a remote player on cellular,
- House Cats.

Each platform's PR shows it working with the others, with screenshots or a short recording.

## 10. Order of work

1. **Server** (flag off in production):
   - the TypeScript engine and fixtures,
   - the module and round state,
   - the live stream and its checks,
   - the shared live relay (§6.10),
   - House Cats,
   - the bot soak,
   - the latency tool,
   - tests.
2. **Web**, alongside 3 once the wire and fixtures from 1 have landed:
   - the player (touch and keyboard),
   - the TV page,
   - the shelf,
   - tips,
   - How to play,
   - frame gates.
3. **iPhone, iPad and Apple TV**, alongside 2:
   - the Swift engine (passing every fixture),
   - the SpriteKit box and minis,
   - touch controls,
   - the TV table,
   - the shelf,
   - tips,
   - How to play,
   - frame gates.
4. **Keeping it out of 1.3.** `main` builds 1.3 today, and the app's shelf (`GameCatalog`) and `x-pounce-games` list every game compiled in. So two gates keep Toy Tumble out of any 1.3 build that reaches testers or the App Store: **(call)**
   - **App:** Toy Tumble's catalog entry, and `tumble` in `x-pounce-games`, are on only in Debug builds or when the app's version is 1.4 or later. Release 1.3 builds never show it or ask for it. The iOS PR can merge into `main` while `main` is still 1.3.
   - **Server:** a minimum app version per game. An iOS or tvOS app below 1.4 never gets `tumble`, whatever its header lists. A dev server (`devSpeed` set) skips the check, so Debug builds play it locally and on the dev Worker.
5. **Switch on:**
   - Add `tumble` to `GAMES` once 2 and 3 are merged and cross-play (§9.6) passes. Cross-play runs on a local or dev server with a Debug iOS and tvOS build.
   - The web player and the web TV page get it at once.
   - The app gets it in 1.4, through both gates. The first 1.4 TestFlight build is the first one testers see.
6. **Sites:** per AGENTS.md, the game's site, the studio site, the README and What's new, once it's live. Each only claims what people can use that day.

## 11. Left to the builder

- The exact pivot table, the flick threshold, and how far a drag goes per column on each device.
- The art (cushions, silhouettes, hairball rows, the cat's moods, effects), within §3. A style checkpoint shows the 9 toys and the hairball rows at mini size before production art.
- The event encoding's small details, within §6.3 and §6.4, recorded in `docs/tv-protocol.md` (or a new `docs/live-protocol.md`) and in protocol fixtures.
- Load tool details, and which dev Worker it runs against.
- House Cat scoring weights, within §6.9.
