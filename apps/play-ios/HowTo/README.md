# How to play videos

One short video per game at the top of its How to play page. Everything on screen is the Debug
build's real table in a simulator, played by a UI test with real taps and drags on the app's demo
tables. A ring under the finger shows each touch (`-show-touches`). The captions and the title card are drawn
over it afterwards. There is no sound: every step is a caption, so it works muted.

| File | What |
| --- | --- |
| `beats.json` | The beat sheet: each game's segments and its beats, each with its caption |
| `make.sh` | Records and cuts the videos (run this) |
| `cards.swift` | Draws the title card and the caption overlays from `beats.json` |
| `compose.py` | Lines the beat log up with the recording and cuts the video with ffmpeg |
| `../PounceUITests/HowToVideoTests.swift` | The script: the taps and drags, and when each beat starts |
| `../Pounce/Resources/HowTo/howto-<game>.mp4`, `.jpg` | The output the app bundles: the video and its poster |
| `raw/` | Recordings and overlays (gitignored) |

## Make them again

```sh
HowTo/make.sh              # both games, on a new iPhone 17 Pro simulator it deletes afterwards
HowTo/make.sh tiles        # one game
DEVICE=<udid> SKIP_BUILD=1 DD=<derived data> HowTo/make.sh cat-tower   # an existing simulator and build
SKIP_RECORD=1 HowTo/make.sh   # cut again from raw/ after editing captions in beats.json
```

The videos show the current UI, so make them again after a change to the table, the tile game's
table or the demo tables they are played on. The script is fully scripted: one command, about
five minutes. Check the result frame by frame (`ffmpeg -i <mp4> -vf fps=1/2,scale=248:-2,tile=8x4 sheet.png`):
a caption must sit over the move it names, and nothing may cover the cards it talks about.

Output: H.264 High, 496x1080 (the iPhone 17 Pro screen at 1080 tall), 30 fps, no audio track,
about 1 MB per 20 seconds. The poster is the title card, 1.2 s in.

### How the cut lines up

The UI test writes a line to `raw/<game>.log` as each beat starts (unix seconds), and `make.sh`
records the whole run with `simctl io recordVideo`. The recording's own timestamps can't be
trusted: on a busy Mac simctl stalls for seconds at a time and its timeline falls behind. So the
app runs with `-timecode`, which draws the wall clock in binary in a thin strip along the top edge
of every frame. `compose.py` reads that clock off each frame, lays each segment out in real time at
30 fps (a stall shows as a held frame), and crops the strip off. Each segment runs from its `from`
beat (less `lead` seconds) to its `to` beat; the segments are crossfaded after the title card, and
a caption shows from its beat to the next one.

## The beats

### Cat Tower (`-demo howto`, then `-demo celebrate`)

`-demo howto` is round 3 on my draw step, level 2 (a set of 3 and a run of 4), with Leo's set of
7s and run 4-7 laid. `HowToSocket` takes my whole turn as the server would, then the others play.

| # | Caption | On screen |
| --- | --- | --- |
| 1 | Climb all ten levels of the tower. | The tower tab opens the tower |
| 2 | This round: a set and a run. | The two trays, 3 and 4 |
| 3 | Start your turn: draw a card. | Tap the deck: the third 9 |
| 4 | Tap a card, then a tray. | 9, 9, 9 into the set tray; 4, 5, 6 into the run tray |
| 5 | Yarn is wild. It fills any gap. | Drag the Yarn to the end of the run: it is the 7 |
| 6 | Level done? Lay it down. | Tap the lay-down paw |
| 7 | Then add to any laid group. | Drag the 8 onto Leo's run |
| 8 | End your turn with one discard. | Pick up the Cucumber |
| 9 | A Cucumber makes a cat skip a turn. | Drop it on Leo: he is skipped |
| 10 | Then the next cat plays. | Kiki and the House Cat draw and discard |
| 11 | Out of cards? The round ends. | Kiki goes out |
| 12 | Cards left in hand cost points. | The points pop |
| 13 | Made your level? Climb a shelf. | Two cats climb the tower |
| 14 | New round, next level. | The deal; I lay down level 10 and go out |
| 15 | Finish level 10 first to win! | The crown, then game over |

### Tuna Tiles (`-demo tiles-early`, `tiles`, `tiles-last`)

| # | Caption | On screen |
| --- | --- | --- |
| 1 | Empty your stash onto the rug. | The stash and the rug before my first play |
| 2 | A match: one number, different toys. | Three 5s, then the new-set slot |
| 3 | Your first play must add up to 30. | The meter: 15 of 30 |
| 4 | A row: one toy, counting up. | Fish 10, 11, 12: 48 |
| 5 | 48 points. Tap Play! | Play; the meter is gone |
| 6 | Then everyone else takes a turn. | The others play |
| 7 | Nothing to play? Hold Draw. | Hold Draw: a toy comes from the toy box |
| 8 | After that, add to any set. | Drag fish 7 onto the fish row |
| 9 | Yarn is wild. Swap in the real toy. | Bell 7 takes the Yarn's place; the Yarn moves to 9 |
| 10 | Move anything on the rug. | 13 fish and 13 mouse make a new set; open the bell row and drag its Yarn over |
| 11 | Every set good? Tap Play. | Play |
| 12 | Play your last toys... | The last three pieces onto rows |
| 13 | Stash empty first? You win! | Play, and the game over card |
