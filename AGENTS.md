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

First-time guidance uses the tip system (`PounceKit/Tutorial`, `Pounce/Shell/CoachMark.swift`): one
short tip at a time, pointing at the thing it's about, shown when it's relevant, dismissed by using
the thing or a tap, and never shown again once learned. A new feature that needs explaining gets a
tip, not more text on the screen.
