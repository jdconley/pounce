# Manual checklist

Checks no script can reach. For JD, and for the PR description. Tick them off on real hardware.

## Real phones over Tailscale

Setup: see "Play on your phone" in `README.md` (`scripts/dev-server.sh`, `scripts/tailnet-serve.sh up`,
`Config/Local.xcconfig`, run from Xcode). Run `scripts/tailnet-serve.sh down` afterwards.

- [ ] Install on two real phones and play a full game: one phone with a pass-and-play seat, a bot in
      the game, through round over, the next deal, and game over.
- [ ] Haptics feel right on device (draw, discard, hit, Cucumber skip, going out).
- [ ] Dragging a card over laid groups on a small phone: the ring and gap follow the finger, a light
      tick on each new group or end, and a Yarn let go at the start of a run lands at the start.
- [ ] Sound levels are sensible next to music and with the ringer switch on and off.
- [ ] Join by typing the room code on the second phone (share links use `play.conleychaos.com`).

## Needs the deployed server (`play.conleychaos.com`)

- [ ] The Messages invite bubble shows the cat art.
- [ ] The universal link from Messages opens the app straight into the lobby (needs the deploy and the
      apple-app-site-association file).
- [ ] The QR code in the lobby joins from the other phone.
- [ ] On the first TestFlight build, confirm the exported app's `aps-environment` is `production`
      (the Release archive relies on export re-signing; the source entitlements say `development`):
      `codesign -d --entitlements - <path to the exported Pounce.app>`.
- [ ] A real "your turn" push arrives on a TestFlight build (Debug builds get sandbox tokens and never
      receive production pushes).

## Accounts, sync and age (daily habit PR 2)

Needs a TestFlight build (Sign in with Apple and Declared Age Range need the real services; Debug
builds stub them only under `-stub-accounts` and `-age-range`).

- [ ] Fresh install: Apple's Declared Age Range sheet appears before pick-a-cat. Decline it: the
      birth-year keypad appears with four empty tiles; after the check it never comes back, even
      after deleting and reinstalling the app (the band is in the Keychain).
- [ ] Sign in with Apple from the people sheet on a guest iPhone: Apple's sheet asks for no name or
      email; the owner's cat gets the lime check; tables and streaks stay.
- [ ] Sign in on the iPad with the same Apple ID: the two cats merge, the iPad shows the iPhone's
      name and cat, the iPhone's household people appear (with a cloud), and the account's tables
      are on Home. Archive a table on one device, foreground the other: it's archived there too.
      Turn sound off on one: off on the other after a foreground.
- [ ] iPad and iPhone in the same seat: take the turn on the iPhone; the iPad's "your turn"
      notification for that table disappears and its badge drops (best effort, background push).
- [ ] Hold a household cat on the people sheet: that person signs in with their own Apple ID and gets
      their own check; the owner stays signed in.
- [ ] Gear sheet: sign out (the account's household people leave; this device plays on as a guest),
      sign back in, then delete the account: confirm, then the Settings path picture. Check that
      Settings, your name, Sign in with Apple lists Pounce until you stop it there (or until the server
      has `PLAY_API_SIWA_KEY_P8`, when deletion revokes it).
- [ ] The gear sheet's hand opens `play.conleychaos.com/privacy`.
- [ ] An account under 13 (Family Sharing child): no sign-in offer anywhere, the name is dice only, no
      share buttons in the lobby, and no "your turn" pushes from the server.
- [ ] In Texas, Utah or Louisiana with a teen account that existed before this build: a parent
      approval request goes out (PermissionKit) and sign-in stays hidden until the parent approves.

## Streaks, looks and Play again (daily habit PR 4)

Needs the server with `STREAKS` on (production once this PR deploys).

- [ ] Two phones, two people, one table: each takes a turn. The second turn stamps both badges at
      the table (double paw, the numeral to 1, a toy into the badge), and Home's badge shows 1 with
      both paws lit on each phone.
- [ ] The next day, before anyone plays: both paws grey, the count still shows; after one turn, one
      paw lights on that phone only for the person who played (a small stamp).
- [ ] Reaching 3 as a guest: the cloud with a plus shows on the badge and on the Us screen; a kitten
      phone never shows it.
- [ ] A gift at 3 opens on the Us screen (wiggle, burst, the reward on the sunburst) and its rug or
      back shows up in the table menu's look tray right after.
- [ ] Change the rug from one phone: the other phone's rug cross-fades at once and the pill with the
      changer's cat floats down. A second change within 10 s shakes the tile.
- [ ] Pause 3 days from one phone: the suitcase shows on both phones' badges.
- [ ] Leave from one phone: it disappears on the other with no push; the leaver's ghosted cat starts
      a fresh pair at 0.
- [ ] Play again at game over: the phone that tapped goes to the new table; the other phone's pill
      bounces and jumps there.

## Notifications and Pounce (daily habit PR 5, TestFlight builds only)

- [ ] Pounce from one phone to another (Us screen bell, New game): the other phone gets "Mia wants
      to play. New game?" with Mia's cat as the avatar and the recipient's name still showing. Play
      deals a table seating both and opens it; the sender gets "JD is coming." and their bell shows
      the leaping cat.
- [ ] Long-press a pounce on the Lock Screen: In a bit and Not now answer without opening the app
      (the sender sees the clock or the sleeping cat). Repeat with the phone in Airplane Mode, then
      turn it off and open the app: the answer goes out once.
- [ ] Three pounces in an hour from one phone: the bell falls asleep and won't open the sheet.
- [ ] Pounce through Messages (the sheet's share button): the link's card shows the bell and the
      sender's name; with the app installed it opens the pick sheet; without it, the TestFlight page.
- [ ] A kitten's phone: no share button on the Pounce sheet, the settings panel has only the 17:00
      bell, and no push of any kind arrives.
- [ ] A fresh install: "not now" on the priming screen, then a "your move": it arrives quietly in
      Notification Center with iOS's Keep and Turn Off; Home's bell offers the full prompt once.
- [ ] Your move's In an hour: the same notification comes back an hour later, and not at all if the
      move was taken in the meantime.
- [ ] Settings panel: change the weekday dial and quiet hours on the iPhone; the iPad (same account)
      shows the same values after a foreground.

## Widgets (daily habit PR 6, TestFlight builds for push)

- [ ] Add the Us widget (small and medium) and the Streak widget (circular, rectangular, inline):
      each shows the top pair; edit one to another partner and it follows that pair.
- [ ] Take a turn at a shared table on the other phone while this one is locked: within a few
      minutes this phone's widgets show their paw lit (WidgetKit push; at most one every 15 minutes).
      The same from a "your move" push (PounceNotify writes the snapshot): the paw lights with it.
- [ ] Medium widget's bell, phone unlocked: the other phone gets a "you pick" pounce and the bell
      turns into the check; an answer (or an hour) brings the bell back. Locked: the bell does nothing.
- [ ] At 04:00 the widgets go grey for the new day without opening the app; a pause that ended
      loses its suitcase.
- [ ] StandBy at night (charging, on its side): the sleeping cats and the numeral, red in night mode.
- [ ] Glass, clear and tinted home screens and the lock screen: the cats and condo draw as mono
      art, the numeral picks up the tint.
- [ ] A kitten's phone: the widgets work and refresh when the app opens, and no widget push ever
      arrives (the token never leaves the phone).
- [ ] Tap each widget: small and rectangular open your move's table, else the Us screen on that pair;
      circular opens the Us screen; a medium row opens its table.

## Live table (daily habit PR 7, TestFlight builds only)

- [ ] Two phones at a table, both open. Lock this phone on the other person's move: within a few
      seconds the live table appears on the Lock Screen (rug strip, their cat ringed, phase
      numerals, the table name, the paws) and in the Dynamic Island (your cat, their cat).
- [ ] The other person plays: the live table lights up with the bell and the turn sound, and no
      separate "your move" notification arrives. (If the app didn't get time to upload the
      activity's token, the regular "your move" arrives instead: note which.)
- [ ] The other person plays again on a bot or a third seat: the ring moves, quietly.
- [ ] Open the app at that table: the live table goes at once.
- [ ] Leave it 30 minutes with no move: it goes by itself; if it was your move, a quiet "your move"
      waits in Notification Center.
- [ ] Swipe it away on the Lock Screen while the app is running: the next "your move" arrives as a
      notification.
- [ ] Gear sheet: turn the live table off, lock on their move: nothing appears. Turn it back on.
- [ ] Round end: the live table goes when the round is over.
- [ ] Answer a pounce with Play, open the table, lock the phone before the other person arrives:
      the live table starts anyway.
- [ ] A kitten's phone never shows a live table; a teen's shows none between 00:00 and 06:00.
- [ ] Two tables: lock on one, come back and lock on the other: only the newer live table stays.

## Parent consent for kittens (daily habit PR 9, TestFlight builds and real codes)

Needs the four `PLAY_API_TWILIO_*` secrets (Twilio Verify, root README); without them the parent's
send leaves the kitten on the hourglass.

- [ ] A kitten's own phone (age keypad under 13): the gear shows the padlocked bell and six numerals.
- [ ] A signed-in adult's phone: gear, Kittens, plus, enter the six numerals: the kitten appears with
      the hourglass; the kitten's bell falls asleep within 15 seconds.
- [ ] The phone button: the notice page loads, enter a real mobile number, send: the keypad replaces
      the notice and a text arrives ("Your Pounce verification code is: …"); the card shows the phone.
- [ ] A wrong code shakes and clears. The loop arrow is dim for 30 seconds, then sends the same code
      again. After 10 minutes the old code is refused and the loop arrow bounces: a fresh code works.
- [ ] The right code: the sheet closes, iOS asks this phone for notifications (allow), the card shows
      the bell with a small hourglass, and the kitten's bell rings (the normal bell).
- [ ] Toggle a person on, have them move at a shared table while the kitten's phone is locked: "your
      move" arrives. Toggle them off: nothing arrives. Their pounce: the same.
- [ ] A day or so later (between 10:00 and 20:00), the parent's phone shows a notification with the
      kitten's name. The card's bell now has a check. A tap opens Kittens on that kitten.
- [ ] Press and hold that notification, then Revoke (Face ID or the passcode if locked): the kitten's
      bell sleeps again and no push arrives.
- [ ] On a parent phone that never allowed notifications for Pounce (deny the prompt after the
      code), give consent: a day after the confirmation was due it ends by itself (the card back to
      the hourglass). A phone that allowed them once and turned them off later still counts as
      delivered: APNs accepts the push.
- [ ] Give consent again, then revoke from the panel (the bell with a slash): pushes stop at once.
- [ ] With Screen Time Communication Limits on the kitten (Family Sharing): a padlocked person in the
      Pounce sheet, tapped, shows Apple's ask; approve in Messages: the padlock goes and the parent's
      toggle shows it, read-only.
- [ ] In App Store Connect's sandbox, withdraw the significant-change approval for the kitten: a
      `RESCIND_CONSENT` arrives (sandbox notifications on) and consent ends.

## Streaks on Home, the trophy room and adding people (TROPHY on the deployed server)

- [ ] A phone with no connections: Home's strip shows your own streak and the big bouncing plus.
- [ ] Tap the plus: the invite sheet shows a QR. On a second phone, point the Camera at it and tap
      the banner: Pounce opens on the pick sheet with your cat; Play deals a new table for both.
- [ ] Back on the first phone's Home (foreground it): the new person's chip is there at 0, before
      either of you has played. The second phone's Home shows yours.
- [ ] The plus's share button sends the same link through Messages; opening the sheet again within
      the hour shows the same QR.
- [ ] Take a turn at that table: your own streak's chip goes up by one when you're back on Home. A
      table of you and bots alone never moves it.
- [ ] Tap your own streak: the trophy room shows your records, the shelf, the locked silhouettes with
      rings, your connections (a tap opens Us on that pair) and the plus.
- [ ] A kitten's phone: the plus shows a room code and its QR, no share button; scanning it with
      another phone's Camera opens that table's lobby.

## Rating ask (version 1.1)

No script reaches this: the ask never runs under a demo, a UI test or any debug launch argument.
The rules are in `PounceKit/Sources/PounceKit/Store/RatingPrompt.swift`; what the device
remembers is `rating.json` next to `people.json`.

- [ ] An adult's phone, at least three days after its first launch of 1.1, with one finished game
      behind it: win a game against a House Cat and stay on the game over screen. Apple's rating
      sheet comes up about five seconds after the screen appears (a TestFlight build shows the
      sheet but can't submit).
- [ ] It doesn't come up after a loss, after a win by forfeit, with two people sharing the phone, or
      on a table that was already over when it was opened.
- [ ] Win again the same day: no second sheet.
- [ ] Gear, Rate Pounce (an adult's phone only) opens the App Store's review page for Pounce. A
      kitten's and a teen's gear has no such row.

## Performance and accessibility

- [ ] Instruments idle-CPU check on the oldest iPhone available: the table scene should pause when
      nothing animates (CPU near zero, no sustained frame work).
- [ ] VoiceOver pass through a full turn: Home, lobby, draw, hit or meld, discard, a Cucumber target,
      round over.
- [ ] Reduce Motion pass: leaps, sunburst and shakes tone down and nothing is stuck.
- [ ] First-game tips with a real first-timer: the bubbles read well, point at the right thing, and
      never get in the way of a move. VoiceOver reads each tip when it appears.

## App updates (needs a device and a server with the update routes)

None of this runs in a simulator: it has no App Store, no TestFlight and no production StoreKit.

- [ ] An App Store install with an older version, once a newer one is live: Home shows "A new Pounce is
      ready" once, Update opens Pounce's App Store page, and the card doesn't return for that version.
- [ ] A TestFlight install: no soft card. The table card and the full screen say "Open TestFlight", and
      it opens Pounce in TestFlight (with no beta link from the server it falls back to `itms-beta://`).
- [ ] A link to a table of a game this version can't draw: "This table is playing <game>. Update Pounce
      to join.", and the table is on Home behind a padlock afterwards. Typed on Join, the same.
- [ ] With `APP_MINIMUM` above the installed version on a test server: the full "Update Pounce to keep
      playing" screen at launch, over everything, and it goes away once the minimum is taken back.
- [ ] A child's device (under 13): none of these has a button, only "Ask a grown-up to update Pounce."
- [ ] The update push on a version 1.0 build: it shows as a banner, and a tap only opens the app.

## Rerun on a quiet Mac

These were not proven. On the shared development Mac, other projects' simulators starved the
renderer, so the runs below timed out or stalled. Rerun them with nothing else booted.

- [ ] `scripts/ui-tests.sh` reaches `** TEST SUCCEEDED **`. The last run had 4 timing failures:
      Celebration game over, Hardening short press, MixedSeats, Smoke live.
- [ ] `MixedSeatsTests` runs end to end.
- [ ] `scripts/multi-sim.sh` plays the full two-simulator game to game over. The last attempt stalled
      for 900 s at simulator A's seat-1 turn after the seats moved. It may be environmental or a real
      bug: if it stalls again on a quiet Mac, treat it as a bug and look at the seat hand-off.
- [ ] Retake `celebrate.jpg` with `scripts/screenshots.sh` once the shelf climb has landed in the
      celebrate demo (adjust `CELEBRATE_AT` if the moment is off).
