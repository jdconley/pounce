# App Store captions (Pounce 1.4)

The headline on each screenshot, in upload order. The same ten for iPhone (`iphone-N.jpg`) and
iPad (`ipad-N.jpg`). The source of truth is `captions.json`, which `compose.swift` reads. Shots 2
(Toy Tumble) and 3 (Purrtrait) are new in 1.4; Birdwatch's trump shot and the levels shot are gone,
and every shot was taken again from the 1.4 build.

| # | Caption | Screen | What backs it |
| --- | --- | --- | --- |
| 1 | Family game night, every night | The card table on your turn | Turn-based play: a table waits for each player's move, so a game can have a turn to take any night |
| 2 | New: Toy Tumble, everyone at once | Toy Tumble mid-round: your box filling with toys, three other boxes beside it | Toy Tumble: every box plays at the same time, two to six players (`GameCatalog.tumble`) |
| 3 | New: Purrtrait, draw for the room | The drawer's phone: "kitten" and a cat half drawn, the colours, Got it | Purrtrait: one phone draws, the TV shows it, the room guesses out loud (`GameCatalog.purrtrait`, `HowToGuide`) |
| 4 | Birdwatch, play as a team | Birdwatch mid-trick: three cards on the sill, the bid, trump, the two team scores and a hand with the Bird | Birdwatch: two teams of two at four players (`HowToGuide.birdwatch`), cards you can't play dimmed |
| 5 | Four new puzzles every day | The Daily Dish: Sniff, Nine Lives, Cat Nap and Box Fort, all done, and the family board | The Daily Dish: four puzzles a day (`DailyCatalog`), a board of you and the people you have a streak with, and a streak per puzzle |
| 6 | Three lives, free hints | Nine Lives, half filled: three cat heads for lives, Hint with 3 left | Nine Lives rules: `lifeCount = 3`, `hintCount = 3` (`NineLivesRules`) |
| 7 | Play your person. Keep the streak. | The Us screen: a 128-day streak with one person | Pair streaks, gifts and the cat condo |
| 8 | Room for the whole family | A full lobby: five people and a House Cat | Six seats at a card table, ten at Purrtrait; House Cat bots fill empty ones |
| 9 | Safe for kids. No chat. No ads. | A child's first launch: pick a cat, a name from the list | No chat in the app, no ad SDK, under-13 names come from a list |
| 10 | Take the crown | Game over: the winner crowned | The win celebration |

The Apple TV shots (`tv-N.jpg`) carry no captions: 1 home (six posters: Cat Tower, Tuna Tiles,
Birdwatch, Toy Tumble, Purrtrait and Tonight's board), 2 a Toy Tumble table, 3 Purrtrait (the
drawing as it's drawn), 4 Birdwatch, 5 Tonight's board (the Daily Dish on the TV), 6 the lobby,
7 Cat Tower, 8 Tuna Tiles, 9 game over, 10 a Sniff run watched from the board.


The app previews (`iphone-preview.mp4`, `ipad-preview.mp4`) carry no text overlays.
Suggested poster frame: the default (0:05, the table with two sets laid down), or 0:01 (the table on "Your turn!").
