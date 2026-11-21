# Sniff's words: where they come from

Sniff's lists are our own, built by `build-words.mjs` from **SCOWL** (Spell Checker Oriented Word
Lists) by Kevin Atkinson, version **2020.12.07**:

- Download: <https://downloads.sourceforge.net/project/wordlist/SCOWL/2020.12.07/scowl-2020.12.07.tar.gz>
- sha256: `5587667caa20c4891390c2d42dbb4d5c4c3f41bee77af1457ece3ba23fb859cc`
- Licence: permissive (MIT-style). Use, copy, modify, distribute and sell, with the copyright and
  permission notice kept in the supporting documentation. Its sources (Moby Words II, Brian Kelk's
  UK English Wordlist, 12Dicts) are public domain. The full notice is in
  [`SCOWL-LICENSE.txt`](SCOWL-LICENSE.txt), copied unchanged from the release.

Nothing comes from Wordle, the New York Times or any other game's lists.

## What we made from it

| File | What | Ships to |
|---|---|---|
| `allowed.txt`, `allowed.ts` | Every five-letter word a player may guess: SCOWL's English, American, British, Canadian and Australian word lists and their first variants, levels 10 to 80, lowercase letters only. | the server, the web player, and the app (`apps/play-ios/Pounce/Daily/Sniff/sniff-allowed.txt`) |
| `answers.txt`, `answers.ts` | The words Sniff may pick as a day's answer: English and American, levels 10, 20 and 35, as tiers 1, 2 and 3 (commonest first). | the server only |

Both drop offensive and adult words: whatever the server's name filter
(`src/names/filter.ts`) refuses, plus `blocked.rot13.txt` (ROT13, so the repo doesn't spell them
out; decode with `tr a-z n-za-m`).

Answers also drop:
- plurals and verb forms made by adding s or es, and past tenses made by adding d or ed, when the
  base word is common (SCOWL level 50 or under);
- the hand pass in `answers-cut.txt`: words a parent would wince at, gloomy ones, slang, rare and
  foreign words, odd comparatives.

## Changing them

Edit `blocked.rot13.txt` or `answers-cut.txt` (or the script), then run:

```bash
node apps/play-api/src/daily/sniff/words/build-words.mjs
```

It downloads SCOWL, checks the sha256, and rewrites the lists and the app's copy. `words.test.ts`
checks the result. Changing the answers reshuffles which word each future day gets (a day already
made keeps its word: `DailyPuzzle` stores it), and may repeat a word sooner than a full cycle.
