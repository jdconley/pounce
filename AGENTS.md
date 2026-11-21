# Working on Pounce

Start with the [README](README.md) and, for the app, [apps/play-ios/README.md](apps/play-ios/README.md).

## Design: change the screen, not just the feature

Pounce should look and read like a professional game. Every UI change is a design change to the
whole screen it lands on.

- **Redesign, don't tack on.** Adding a control, card, row or message means reconsidering the
  screen as a whole: hierarchy, grouping, spacing, what can be merged, moved or removed. If a new
  thing doesn't fit, rework the layout so it does. Don't stack it on top or squeeze it in.
- **Show it.** A PR that changes UI includes before and after screenshots of every screen it
  touches.
- **It has to fit.** Check each changed screen on the smallest supported iPhone (iPhone SE), a large
  iPhone, iPad portrait and landscape, and the largest accessibility text size. Nothing clips,
  overflows, overlaps or collides with the cat, the bars or the safe areas. Long names and big
  numbers are part of the test.
- **Fade groups, not pieces.** When a group of overlapping things is made translucent (a stack of
  cards, a dimmed set of pieces), fade the group as one layer so nothing shows through from behind:
  `.compositingGroup()` in SwiftUI, a flattened or rasterized node in SpriteKit. Never fade the
  overlapping pieces one by one.

## The main thread draws, nothing else

Pounce runs at 60 frames a second or better, always, and at 120 where the screen can. So on every
platform (iOS, web, Android) the main, UI or render thread does UI work only: layout, drawing,
input, animation and small state updates. It never touches the disk or the Keychain, never waits on
the network, never sleeps, locks or blocks, never dispatches synchronously, and never runs heavy
compute (the solver, bots, hint search, big encodes or decodes). Main-thread work stays under 8.3 ms
a frame and is never over 16.7 ms.

- Blocking calls live in each platform's one IO layer, off the main thread by construction, with an
  async API. Everything else reads memory and hands changes to that layer.
- The static checks fail the build on a violation (iOS: `apps/play-ios/scripts/main-thread-lint.swift`
  in CI). Don't silence one; move the call.
- The UI tests fail on a main-thread hang or frames over budget.

[docs/main-thread.md](docs/main-thread.md) has the full rule, each platform's checks and the allowed
pattern.

## Words in the UI

The UI is not where we explain things. Every word costs attention.

- Buttons and labels: one to three words. Messages: one short sentence, or a fragment.
- Say what happens, not why. Cut "you can", "simply", "in order to", greetings, reassurance and
  repetition of what the screen already shows.
- Teach with tips and How to play, not with paragraphs on screens. How to play (and its video) is
  the one place for longer explanations.
- Plain words, no jargon, no emoji anywhere.
- The tagline is "Family game night, every night".

## Guiding people

First-time guidance uses the tip system (`PounceKit/Tutorial`, `Pounce/Shell/CoachMark.swift` for
the game's rules, `Pounce/Shell/Tips.swift` and `UITips.swift` for the app's controls): one
short tip at a time, pointing at the thing it's about, shown when it's relevant, dismissed by using
the thing or a tap, and never shown again once learned. A new feature that needs explaining gets a
tip, not more text on the screen.

## Testing on this Mac

Keep Pounce silent when you test it locally. Many sessions run simulators at once, and Simulator
has no mute, so turn off the game's own sound instead:
- After you boot a simulator, and before you launch Pounce, run
  `xcrun simctl spawn <udid> defaults write com.conleychaos.play settings.soundOn -bool NO`. On an
  Apple TV simulator, also run it for `tv.soundOn`. If the app is already running, relaunch it.
- For UI tests and `-uitest-reset` launches, pass the launch arguments `-settings.soundOn` `<false/>`
  (Apple TV: `-tv.soundOn` `<false/>`). Never pass a bare `NO`. The argument domain stores it as the
  string "NO", `Settings` reads it as no value, so the sound stays on, and it also overrides the
  `defaults write`.
- Run headed Chromium with `--mute-audio`. Headless is already silent.

This is only about local runs. Leave the sound code and its default alone.

## Releases

Every merge to `main` that touches `apps/play-ios` uploads a TestFlight build and sends it to the
Family and Friends group as well as the internal testers. The build's "What to Test" notes are the
squash-merge commit subjects since the group's last build, so a PR that changes the app gets a title
a family member can read: what changed for them, in plain words ("Draw is a tap; the toy box moved
off the rug"), not how it was built.

### Every release updates the websites

The websites say what Pounce does today, never what it did two releases ago. When a release goes
out, the same change (or a follow-up PR you open right after it lands) updates every page that
describes Pounce. Don't hand it to someone else, and don't wait to be asked.

A release is any of these:
- An App Store version goes live. Check with
  `curl -s "https://itunes.apple.com/lookup?id=6829560061&country=us"`.
- A change people can see reaches production on the web. Every merge to `main` deploys
  `play.conleychaos.com`, the web player and the TV page.
- A new game, platform or way to play: a browser player, a TV, a new device.

Update each place that the release makes out of date:

| Where | Files |
|---|---|
| play.conleychaos.com, the game's own site | `apps/play-api/src/http/home.ts`, its screenshots in `apps/play-api/public/media`, its OG text and structured data, and the `/j/` and `/p/` invite pages in `apps/play-api/src/http/links.ts` |
| conleychaos.com, the studio site | repo `jdconley/conleychaos`: `apps/conleychaos-site/src/data/games.ts`, `public/llms.txt`, screenshots in `public/media/pounce/`, and that repo's tests |
| This repo | the version table and feature list in `README.md`, and `docs/whats-new/<version>.md` |
| JD's GitHub profile | repo `jdconley/jdconley`, `README.md`, for App Store releases |

Rules for that copy:
- Claim only what people can use today. TestFlight-only and in-development features (for example
  an app that hasn't passed review) are not "available". Leave them out, or say "coming".
- Keep the parents' notice and the privacy facts true. App Review reads them.
- Use plain words with no emoji. Keep the tagline "Family game night, every night". conleychaos.com
  never mentions Meanwhile.
- After the deploy, open the live pages and check them. If a deploy can't run (for example GitHub
  Actions billing on `jdconley/conleychaos`), say so in the PR and tell JD; never call the site
  updated until it is live.
