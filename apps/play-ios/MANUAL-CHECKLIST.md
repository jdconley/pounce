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
