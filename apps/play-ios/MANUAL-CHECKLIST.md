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

## Performance and accessibility

- [ ] Instruments idle-CPU check on the oldest iPhone available: the table scene should pause when
      nothing animates (CPU near zero, no sustained frame work).
- [ ] VoiceOver pass through a full turn: Home, lobby, draw, hit or meld, discard, a Cucumber target,
      round over.
- [ ] Reduce Motion pass: leaps, sunburst and shakes tone down and nothing is stuck.
- [ ] First-game tips with a real first-timer: the bubbles read well, point at the right thing, and
      never get in the way of a move. VoiceOver reads each tip when it appears.

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
