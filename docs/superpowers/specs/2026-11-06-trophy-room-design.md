# Streaks on Home, the trophy room, and adding people: design addendum

An addendum to `2026-11-04-daily-habit-design.md` (§7, §9, §10.1, §10.2, §12.4, §14.1).

## Why (JD, 2026-11-06)
After installing build 202611060055, JD couldn't find a way to connect with his wife or kids. Pairs form only by playing a game together, and nothing on Home says so. In his words:

> "a trophy room sort of place where you can see your streaks and things you've earned … and things that are available to earn … people you're connected with and what their streaks are … if you don't have any connections, you should be able to add one by inviting someone … really obvious on the homepage … your own streak for playing, and then your streaks with connections, just like right there on the home screen."

## What other games do (coordinator research, 2026-11-06)
- **Duolingo friends** are added from the profile: contacts sync, username search or a shared profile link.
- **Duolingo Friend Streaks** need a mutual follow and an accepted invite, allow up to 5 friends, and end on a missed day.
- **Duolingo achievements** moved from a buried spot to a prominent "trophies on a shelf" area, with personal-record badges such as Longest Streak.
- **Snapchat** keeps a private count per friend in the chat list, which is widely criticized for the pressure it puts on teens.
- **Couples apps** (Cuplido, PairStreak) use one shared streak with forgiveness.
- **Apple's Games app** (iOS 26) uses Game Center achievements and friend challenges.

Pounce takes the shelf and the accepted invite from Duolingo, and keeps the shared streak with forgiveness it already has. It doesn't sync contacts or search usernames: §14 says invites are by code or link only, which matters with kids.

## 1. Home: the streak strip
The single paw badge at top center becomes a **strip**, in this order:

1. **Your own streak** (§2): a paw with your cat and the numeral. A tap opens the trophy room.
2. **One chip per connection,** in top-pair order (§7): their cat, the two paws and the pair's numeral, with the same marks as the badge (bandage, suitcase, nap blanket, sparkle). A tap opens the Us screen on that pair.
3. **A plus chip, always last.** A tap opens the invite sheet (§4).
   - **With no connections,** it is the big, bouncing first thing after your own streak: the "Add someone" entry.

Details:
- No words, as everywhere.
- The strip scrolls sideways when there are more chips than fit. On iPad it has room for all of them.
- The gift box and the sign-in cloud stay where PR 4 put them.

## 2. Your own streak (reverses §7's "no personal streak", JD)
- §7 ruled a personal streak out because it would reward playing alone against bots. JD now wants "your own streak for playing" on Home.
- **Day rule (D1):** a day counts when you take a turn at a table with at least one other human.
- It uses the pair streak's day boundary (04:00 local), the same nap rules (§8.1), and the same fresh start (§8.4).
- No gifts or toys, since those stay with pairs. It gets **personal records** instead (§3).

## 3. The trophy room (new screen)
Opened from your own streak chip, and from the Us screen's top bar.
- **Personal records:** icon-and-numeral tiles for your current streak, your best streak, your longest pair streak ever, the total days you've kept, and perfect weeks.
- **The shelf:** everything you've earned across all your pairs, meaning toys, card backs, rugs and the highest condo stage, drawn as loud trophies.
- **Still to earn (D4):** locked silhouettes for every catalog item you haven't earned. Each has a progress ring and the milestone numeral where it unlocks (for example a ring at 30 on the 30-day gift).
- **Connections:** each person's cat, name and pair numeral. A tap opens the Us screen.
- **Invite:** the same plus as on Home.
- iPad gets a roomier layout, as the Us screen has.

## 4. Adding someone: the invite sheet
- **A Messages link,** sent through the system share sheet. It is PR 5's link pounce, with no `to` and target `"new"`.
- **A QR code** of the same link, for in person: the other phone scans it with the Camera app and the universal link opens Pounce.
- **The connection appears on accept (D2):** answering the link creates the pair at once at count 0, deals a new table for both, and shows the new chip on both Homes.
- No contacts sync and no usernames (§14).
- **Kittens** (§14.1, unchanged):
  - A kitten's device can't send links, so the plus there shows a **room code** (the same five-character code the lobby shows) and its `/j/` QR instead, for in-person play only.
  - A kitten *can* accept an invite, because nothing is collected from them.
  - Pushes still follow PR 9's consent rules.

## 5. Server
- A new `TROPHY` flag, which requires `STREAKS`. With it off, the server answers exactly as today.
- **Player:** a personal streak record (count, best, last day, naps, total days kept), updated from the turn reports the room already makes.
- **New route:** `GET /v1/me/trophies` returns:
  - your own streak;
  - your personal records;
  - what you've earned, merged across your pairs;
  - the catalog with each item's unlock milestone;
  - your connections, which are the existing pair views.
- **The invite answer (D2):** answering a link pounce calls `ensurePair` before dealing the table, and both players' streak lists refresh.
- **No cap on connections (D3).**

## 6. Later, not in this PR
Game Center achievements as an optional extra. They need Game Center accounts, which guests and kids can't count on, so they aren't the friends system.

## 7. Decisions (JD, 2026-11-06)
- **D1, your own streak:** a day counts when you take a turn at a table with another person. Bots alone don't count.
- **D2, connections:** one appears as soon as the invite is accepted, at count 0, with a new game dealt for both.
- **D3, cap:** none.
- **D4, still to earn:** the trophy room shows locked silhouettes with progress rings.
