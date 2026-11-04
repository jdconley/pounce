# Pounce daily habit loop ("Us" streaks) — Design

Date: 2026-11-04 · Owner: JD Conley (Conley Chaos LLC) · Status: **draft v3. JD answered rounds 1 and 2 of the open questions (2026-11-04), and the design is waiting on his approval.** Nothing gets built until JD approves.

Parent specs: `2026-10-31-pounce-cat-tower-design.md` (product and rules) and `2026-10-31-pounce-ios-design.md` (the client). Where this doc changes something they decided, it says so. The biggest change is that **accounts (Sign in with Apple) move from M2 into this work**, because JD wants everything to sync between devices.

Marks: **(JD)** = JD's words or decision; **(call)** = a designer call made while writing this, open to override; **(research)** = follows from a cited source in §4; **(server)** / **(app)** = fixed by what is already built.

---

## 1. Intent

> "i want to play with my wife daily, so let's design something like duo lingo. a home widget that urges you to play something. push notifications to remind you to connect. streaks. rewards for those streaks. … i want this to be addictive, it's for a good cause." **(JD)**

> "i want the streak to be both of us playing together, something that affects the other. … it might even just be making a few moves but in a game together." **(JD, round 2)**

Cat Tower is already a good game for two people who love each other. What it lacks is a reason to open it *today*. Async play makes it worse, because a game can stall for days when nobody notices it's their move. This design adds a daily loop on top of the game:

- a streak you share with each person you play with;
- home and lock screen widgets that keep the streak in view;
- reminders at the time you usually play;
- a way to **pounce**, asking someone to come play right now (the couch-and-TV moment);
- a Live Activity while you're both mid-game;
- accounts, so you and your partner can each play from your iPhone and your iPad and it's all one you;
- rewards themed to the cats.

The aim is a habit in the Duolingo sense, with one difference that shapes every decision. **The streak belongs to the two of you, and it must never become a way for one of you to feel bad about the other.** Sticky, yes. Guilt, blame or nagging, no. A relationship app that sours the relationship has failed, whatever its retention chart says.

**Success:**
- JD and his wife both take a turn in a game together on most days for two months. That's about how long a habit takes to form (Lally et al., §4.5).
- JD also keeps a streak going with his son, his daughter or his mom.
- Both say the reminders feel like the cats asking them to play, not like the app scolding them.

## 2. Goals, non-goals, anti-goals

**Goals**
- **A shared streak for every pair of people who play together** (partner, kids, mom) **(JD)**. A day is kept only when **both** of you took a turn in a game together **(JD)**. Every Pounce game counts, so a future co-op game would too.
- **Accounts that sync everything across devices, and that work with any sign-in provider** **(JD)**: Sign in with Apple first, with others such as Google, email or passkeys later, and no migration. Your identity, seats, tables, archive, streaks, rewards and settings all belong to your player.
- **Sign-in is never required** **(JD)**. A guest has a full streak. Signing in later is an **anonymous upgrade**: the same player gains a sign-in, and nothing moves.
- **The rules for minors are followed** **(JD)** (§14.1).
- **Forgiving by design:**
  - automatic cat naps (freezes);
  - a free way to win back a broken streak;
  - a pause of up to two weeks **(JD)**;
  - a fresh-start moment after a break;
  - a fair rule for when the move simply never reached you.
- **Pounce: ask someone to come play now**, from the app or through Messages. You can point them at an existing table or a new game, or let them pick **(JD)**.
- **Rewards** that fit the Loud Toy art: a shared Cat Condo that grows, toys that drop on kept days, card backs and rugs, and celebrations.
- **Anyone at a table can change its rug and card back**, as in a group chat **(JD)**.
- **Widgets:** home (small, medium), lock screen (circular, rectangular, inline) and StandBy, with a **Pounce** button.
- **A Live Activity** for a live game ("live table"), easy to dismiss, which hides itself after a while **(JD)**.
- **Notifications:**
  - "your turn" now says who played;
  - one daily reminder, at your learned time or a time you set **(JD: adjustable)**;
  - a last-chance reminder;
  - Pounce;
  - adjustable quiet hours **(JD)**;
  - hard caps and backoff.
- **"Play again"** with the same people when a game ends.
- **Server:** players, pairs, accounts and day boundaries in Durable Objects, settled on the server in each person's own time zone.

**Non-goals (this design)**
- A new mini-game. Turns in a real game together are the daily ritual **(JD)**.
- Leagues, XP, leaderboards, or competing with other couples. Pounce isn't social with strangers.
- Purchases of any kind: no paid freezes, repairs or gems. Pounce has no monetization.
- Passwords. Future providers will be passwordless: Google, email one-time codes, passkeys.
- Android and the Mac.
- Analytics.

**Anti-goals** (failure even if it "works")
- **Showing who broke it.** No screen, push or history entry ever says one person missed a day.
- **Confirmshaming or guilt copy:** no "Don't let Mia down", no crying mascot.
- **Notifications that wake you,** or more than two reminders a day.
- **Countdown pressure:** no ticking timers, no "streak ends in 2h 13m".
- **Rewards that feel like gambling:** no currency, no rerolls.
- **Text on screen.** The no-words rule holds: names, table names and numerals only, everything else is art **(JD)**. Push copy is the one place for sentences, and it already uses them **(app)**. The Sign in with Apple button carries Apple's own text, which Apple requires.
- **Emoji anywhere**, including push copy and widgets **(JD)**.
- **Beige, muted, storybook art (JD).**
- **A Live Activity that overstays.** It must end itself and be easy to dismiss **(JD)**.

## 3. Constraints

- iOS 26+, iPhone and iPad, SwiftUI shell and SpriteKit table, Swift 6, Apple frameworks only, XcodeGen `project.yml` **(app)**. Sign in with Apple uses AuthenticationServices, an Apple framework, so no package is needed.
- Bundle `com.conleychaos.play`, team `B222J9J7B8`. New targets get bundle IDs under it: `com.conleychaos.play.widgets` and `com.conleychaos.play.notify` **(call)**. The Live Activity lives in the widgets target.
- **Server:**
  - Cloudflare Workers plus SQLite-backed Durable Objects: `GameRoom` per room, `DeviceIndex` per device **(server)**.
  - APNs is sent straight from the Worker over HTTP/2 with a `.p8` JWT. This already works in production for TestFlight **(server)**.
- **Identity today:**
  - A device has a `deviceId` and an HMAC token. A re-mint after a 401 makes a new device **(app)**.
  - People are created on the phone (`Person {id, name, cat}`, a UUID made on the device), and one phone can hold several (pass-and-play).
  - A seat belongs to a `deviceId` (`SeatInfo.deviceId`, `RoomCore.controlledSeats(deviceId)`), and person ids aren't verified **(server)**. §13.1 replaces this with players.
- **Secrets:**
  - Verifying Sign in with Apple needs none (Apple's public keys).
  - Token revocation needs a Sign in with Apple private key, set like the APNs key as the optional pipeline secrets `PLAY_API_SIWA_KEY_P8` and `PLAY_API_SIWA_KEY_ID`. Without them, revocation stays off, and the server warns, the way push does today **(server)**.
  - JD creates the key once, before App Store submission (§13.1). One key with APNs and Sign in with Apple both enabled can serve both secret pairs.
  - No session ever handles a key.
- **The push path already in the app:**
  - priming (`PushPrimingView.swift`);
  - `PushCoordinator`: token upload every launch, tap routing, and the local 10-minute reminder;
  - the server's `pushYourTurn`, with `thread-id` and collapse id set to the room code **(app)**.
- **Art** comes from the Codex pipeline in `apps/play-ios/Art`, with style reference `chosen-d-loud-toy.png`. Prompts are committed. **Placeholders come first, and JD approves art in batches (JD).**
- **Session rules:** never touch the `:4343` server, work only in a worktree, and keep secrets out of the repo.

## 4. Research

Research was done on 2026-11-04, with web sources in the Sources list at the end. Numbers in brackets like [2] point there. **Unverified** marks a claim found only in secondary or third-party sources. These are not used as the reason for any decision.

### 4.1 Duolingo: how the streak works and what moved retention

- **One small action extends the streak.**
  - In 2020 Duolingo stopped tying the streak to the daily XP goal and made one lesson enough [1].
  - Day-14 retention rose 3.3%, daily active learners rose 1%, and learners on a streak rose 10.5% (19% for new learners) [1].
  - *Taken:* one completed turn keeps the day (§6).
- **The streak is their biggest lever, and they tune it constantly.**
  - Duolingo has run more than 600 streak experiments [11].
  - Retention is most fragile in the first 7 days [11].
  - Learners who reach a 7-day streak are 3.6x as likely to finish their course. This is a correlation [2].
  - Day 2 to 3 is a 50% change in streak length, while day 200 to 201 is 0.5% [2].
  - Former CPO Jorge Mazal says the first big streak win was a late-night **streak-saver** alert. Freezes, calendars and animations came after it [10].
  - Over four years, current-user retention rose 21%, cutting daily churn among the best users by more than 40% [10].
  - *Taken:* quick early milestones at 3 and 7 (§9.2), and a last-chance reminder (§12.1).
- **Freezes.**
  - A freeze covers one missed day and has to be equipped before the miss. It's bought with gems [14].
  - Letting free users hold **two** raised daily active learners by 0.38% relative, without more days off [2].
  - The Weekend Amulet (2017) made learners 4% more likely to return a week later and 5% less likely to lose their streak [4].
  - Duolingo repairs streaks lost to its own outages for free; "BRB" saved more than 2 million [6].
  - **Repair** is paid in gems; the window and price aren't published [14].
  - *Taken:* a shared pool of at most two naps, earned and never bought (§8.1). Repair is earned by playing, not paid (§8.2).
- **Milestone animation.** A new post-lesson streak animation raised the chance a new learner was active 7 days later by 1.7% [2]. *Taken:* the stamp and celebration moments (§9.5).
- **Committing to a goal.**
  - Letting new users pick a streak goal, and changing "continue" to "commit to my goal", "significantly increased retention". No size is given [11].
  - *Not taken in v1:* a goal picker is words-heavy. A part-filled milestone arc does the same job (§10.2).
- **Friend Streak (2024).**
  - Up to five friends, a separate streak with each, and both must do a lesson each day. You can nudge a friend [7].
  - Learners with at least one friend streak are **22% more likely to complete their daily lesson**, and the effect grows with each friend [7].
  - What happens when one friend misses isn't published.
  - Friends Quests pair mutual followers for a weekly shared goal, with preset nudges [8].
  - *Taken:* one streak per pair (§7) and Pounce (§12.4). The "both every day" rule is adopted, as JD asked, with a late move pass for turn-based play (§6.2).
- **Leagues and XP.**
  - Leagues raised total learning time 17% and tripled highly engaged learners, with D1 and D7 retention up [10].
  - *Not taken:* competition between strangers isn't Pounce (§2).
- **The iOS widget (2022).**
  - Half of learners with the widget have a streak of at least six months [9].
  - Widget users retained better even after accounting for adopters already being more committed [9].
  - Feedback rated it as effective as push. Showing the streak and whether it's at risk was "highly valuable" [9].
  - A widely quoted "60% increase in commitment" doesn't appear in any Duolingo source (**unverified**).
  - *Taken:* the small widget shows the numeral plus today's state (§11).
- **Notifications.**
  - Duolingo's KDD 2020 bandit ("Recovering Difference Softmax") chooses **which message template** to send, and penalises a template reused too soon [12].
  - It gained 0.5% daily actives and 2% new-user retention over a strong baseline. Success means a lesson within 2 hours [12].
  - The paper doesn't cover send time.
  - The team's rule is **"protect the channel"**: more notification volume needed the CEO's sign-off [10].
  - After about a week of inactivity, Duolingo says the reminders don't seem to be working and stops (via WSJ [13]; exact trigger **unverified**).
  - A practice reminder about 23.5 hours after the last lesson, a cap of two a day, and a roughly 10 p.m. streak saver are reported only by third parties [59] (**unverified**).
  - *Taken:* send near your usual time; rotate copy and never repeat a line within 7 days; a hard cap of 2 a day; stop after a week (§12.3).
- **Day boundary and time zones.** Duolingo doesn't document these. Its travel advice is to do a lesson before boarding and after landing [3]. *Taken:* our own rule, each person's local day with a 4 a.m. rollover (§6.3).

### 4.2 Couple apps and shared streaks

- **Snapchat streaks.**
  - Both people must send a snap at least once a day. An hourglass appears near expiry. Recently lost streaks can be restored [15][16], for money, or free once a month with Snapchat+ [16].
  - A 2026 Bits of Freedom survey of 300 people aged 13 to 21 (advocacy research, not peer-reviewed) found [17]:
    - 51% would feel bad if the other person broke the streak;
    - 42% would remove streaks if they could;
    - 25% have paid to restore one.
  - *Taken:* this is the failure we design against. No hourglass countdown, no paid restore, and nothing that pins the break on one person (§2, §8).
- **Paired.**
  - The ritual is a daily question, and your answer stays hidden until your partner answers.
  - Streaks are **individual**, so your partner's miss never resets yours. Any one activity before local midnight counts. Freezes apply automatically, and premium users can recover a streak of 7+ days broken less than 7 days ago with 3 activities on the first day back [18].
  - Its top review complaint is the paywall [21].
  - *Taken:* automatic naps and the earned win-back (§8). Paired avoids partner blame by splitting streaks into individual ones. JD wants one streak that takes both of you (§6.2), so we avoid blame differently: the late move pass makes the move reaching you late a non-miss, and no screen ever records whose miss a day was.
- **Locket.**
  - Photos land straight on your friends' home-screen widget. The widget *is* the product.
  - 2M sign-ups in two weeks at launch, with no paid ads [19]. Company-claimed 80M downloads and 9M+ daily actives by 2025 [20].
  - *Taken:* the partner's cat on your home screen is the hook (§11).
- **Lasting, Agapé, Between:** daily check-ins, prompts that reveal once both partners answer, and private couple chat. We found no primary detail on their streaks or widgets (**unverified**).
- **The shared pattern in couple apps:** a tiny daily ritual, a reveal or response from your partner, and a gentle "your partner did theirs". Pounce's version is "Mia played. Your move."

### 4.3 Notifications on iOS and in practice

- **Provisional authorization.** It shows no prompt. Notifications arrive quietly in Notification Center only, each with **Keep** and **Turn Off**. Apple frames it as a trial and recommends asking for full permission in context, not at first launch [22]. *Taken:* provisional after "Not now" on priming (§12.5).
- **Interruption levels** (iOS 15+): passive, active, time-sensitive and critical [23].
  - Passive lands in the list without sound or lighting the screen.
  - Time Sensitive breaks through Focus and the Summary where the person allows it. It needs only the Xcode capability, not Apple's approval. Apple says not to overuse it, and people can turn it off for an app [24].
  - Payload keys: `interruption-level`, and `relevance-score` (0 to 1), which picks what's featured in the Summary [25].
  - *Taken:* passive during quiet hours and for status pushes. No Time Sensitive (§12.5).
- **Grouping.**
  - `thread-id` groups visually [25].
  - `summary-arg` / `summaryArgument` has been **ignored since iOS 15** [26].
  - `apns-collapse-id` (at most 64 bytes) replaces an earlier notification with the same id [27].
- **Actions.**
  - Categories hold up to four actions [31]. `.foreground` opens the app, `.authenticationRequired` needs an unlocked device, and actions without `.foreground` run in the background [28].
  - Apple publishes no time budget for a background action, so keep them short and idempotent [28].
  - The HIG says to offer actions that save time, not ones that only open the app [31].
- **Notification Service Extension.**
  - Runs on `mutable-content: 1`. The notification must have an alert, and the extension has limited time [29].
  - It can turn a push into a **communication notification** (an `INSendMessageIntent` with an `INPerson` avatar), which shows the sender's picture and can break through Focus for people the user allows [24].
- **Apple rules.**
  - App Review 4.5.4: push must not be required to use the app, and no marketing without opt-in [30].
  - 4.5.3: no spam through push or Live Activities [30].
  - 5.1.2: no requiring push to get rewards [30].
  - The HIG says to avoid several notifications about the same thing even if the person hasn't responded, because it leads people to turn notifications off [31].
- **Industry practice.**
  - Evaluate quiet hours in the person's local time [32].
  - Cap frequency over rolling windows.
  - Vendor figures for "pushes per week before opt-out" conflict (**unverified**).
  - *Taken:* local-time quiet hours on the server, a 2-a-day reminder cap, and a 20-minute spacing floor (§12.3).

### 4.4 Widgets and Live Activities

- **Families and looks.**
  - iPhone home screen: small, medium, large. Lock screen: `accessoryCircular`, `accessoryRectangular`, `accessoryInline` [33].
  - Rendering modes: full color, accented and vibrant. Vibrant is used on the lock screen and in StandBy night mode, which tints red in low light [33].
  - iOS 26 adds **clear** (Liquid Glass) and **tinted** home screens. Use `widgetAccentable()` and `widgetAccentedRenderingMode` on images, and `containerBackground(for: .widget)` [34][33].
  - Don't carry meaning in color alone [33].
- **Interactive widgets.**
  - Only `Button` and `Toggle` backed by an `AppIntent`, on system families plus circular and rectangular. Buttons are inactive until the device is unlocked [35].
  - By default the intent runs in the widget extension. iOS 26 replaces `openAppWhenRun` with `supportedModes` [35].
  - WWDC26 says intents get 30 seconds [39].
  - A widget reload after the intent is guaranteed [35].
- **Budget.**
  - A frequently viewed widget gets about 40 to 70 reloads a day [36].
  - Reloads from the foreground app, from an App Intent, and in StandBy don't count against it [36].
  - Do a final reload when the app goes to the background; heavy foreground reloads may be throttled [38].
  - Network from a widget extension is limited and may be cut off [36].
- **WidgetKit push updates** (WWDC25).
  - The widget extension adopts `WidgetPushHandler` and gets a token in `pushTokenDidChange` [37].
  - The server sends `apns-push-type: widgets` with topic `<bundle id>.push-type.widgets` and body `{"aps":{"content-changed":true}}` [37][27].
  - The push carries **no data**: it only triggers a reload of that device's push-enabled widgets, so the provider reads shared storage [37].
  - Pushes are budgeted and delivered when the system chooses, and the minimum OS isn't stated (treated as iOS 26). Apple says to throttle on the server and not to use them for urgent alerts [34].
- **Live Activities.**
  - 8 hours active, then up to 4 more on the lock screen. 4 KB of data. No network access of their own [40].
  - Updated by `apns-push-type: liveactivity` pushes, and push-to-start is supported [41].
  - The HIG says they're for events with a clear start and end, usually under 8 hours. Don't use them for things that go on indefinitely, and don't duplicate push notifications for the same updates [42].
  - *Taken:* no Live Activity for the multi-day game. Only an optional, short "live table" (§11, §15).

### 4.5 Habit psychology and the ethics line

- **Loss aversion is real but not magic.**
  - Losses loom larger than gains [49], but the effect is weaker at small stakes (**secondary**).
  - The streak-specific evidence matters more. Silverman & Barasch (JCR 2023, seven studies) found that an intact streak drives more future engagement than a broken one, and that the drop after a break is **worse when people blame themselves** and **smaller when the streak can be repaired** [43].
  - *Taken:* no blame, and an earned win-back (§6.2, §8.2).
- **Reward the return.**
  - In Milkman et al.'s megastudy of 61,293 gym members (Nature 2021), the best of 54 programs **rewarded coming back after a missed workout** [44].
  - *Taken:* win-back and the fresh-start push (§8).
- **The what-the-hell effect.**
  - A lapse blamed on yourself ("no willpower") tends to snowball into full relapse (abstinence violation effect; **secondary**).
  - *Taken:* never "you missed", and the next step is always one small turn.
- **Habits take about two months, and one miss doesn't break them.**
  - Lally et al. (2010) found automaticity plateaued after a median of 66 days (range 18 to 254). **Missing one opportunity did not materially affect habit formation** [45].
  - *Taken:* naps and pause are not cheating. They match how habits actually form.
- **Goal gradient and endowed progress.**
  - People speed up as a reward nears, and a pre-stamped card is redeemed more [46].
  - In Nunes & Drèze's car-wash study, 34% of pre-stamped cards were completed versus 19% of blank ones [47] (**secondary**).
  - No study tests specific spacings like 3, 7, 14 and 30. Early quick wins with gaps that widen later is an inference from this work.
  - *Taken:* part-filled milestone arcs, and the win-back's two visible dots.
- **The fresh start effect.**
  - Dai, Milkman & Riis (Management Science 2014): new-week, new-month and birthday landmarks raise goal-directed behaviour by opening a "new mental accounting period" [48].
  - *Taken:* the Monday or 1st-of-month push after a break (§8.4).
- **Variable rewards, carefully.**
  - Variable schedules sustain behaviour (Skinner, via Eyal's Hook model [58]; **secondary**).
  - Loot boxes bought with money are linked to problem gambling [51].
  - Tangible rewards contingent on performance can crowd out intrinsic motivation [50].
  - *Taken:* surprises are small, frequent, cosmetic and never bought (toys, §9.3). Keep the game itself the point.
- **Couples.**
  - Everyday small interactions predict how couples handle conflict (Driver & Gottman 2004, "bids" for connection) [52].
  - Doing novel, exciting things together raises relationship quality (Aron et al. 2000) [53].
  - More *solo* gaming time is linked to more conflict for men (Coyne et al. 2012) [54]. Co-play isn't studied.
  - Family step-goal games built on support and collaboration beat control (BE FIT, JAMA IM 2017) [55].
  - *Taken:* frame every turn as a bid your partner can answer ("Mia played. Your move."). Make the shared goal cooperative, never a contest between the two of you. Vary rewards for novelty.
- **Dark patterns.**
  - Brignull's taxonomy includes *confirmshaming* and *nagging*. The FTC's 2022 report covers manipulative design in apps [57].
  - deceptive.design lists Duolingo's paid streak repair as a deceptive pattern [56].

**The ethics line we adopt** **(call, research)**

**Do:**
- The unit is "us".
- Recovery is free and automatic.
- Quiet hours and an off switch are always there.
- A pause exists for life events.
- Rewards are cosmetic.
- The copy is warm and about the cats.

**Don't:**
- Name who missed.
- Shame, through copy or a sad mascot.
- Repeat a reminder after it's ignored.
- Use countdown timers.
- Sell freezes or repairs.
- Require push for anything.
- Let one partner nag the other through the app without a limit.

### 4.6 Sign in with Apple and accounts

- **Verifying a sign-in.** The server checks the identity token's RS256 signature against Apple's published keys, choosing the key that matches the token's `kid`. It then checks `iss`, `aud` (the bundle id, for a native sign-in), `exp` and `nonce`. Apple says to generate a fresh nonce for every request and verify it on the server [60].
- **Account deletion.**
  - Apps that offer account creation must let people delete their account in the app (App Review 5.1.1(v)) [30].
  - Apps that use Sign in with Apple must revoke the user's tokens through the REST API when an account is deleted [61].
  - Revocation takes a refresh or access token, not the identity token. The authorization code lasts only minutes, so the server exchanges it for a refresh token at sign-in and keeps that token [61][62].
- *Taken:* no scopes requested, server-side verification, a refresh token stored only to revoke it, and in-app deletion (§13.1, §14).

### 4.7 Rules for minors

Research was done on 2026-11-04. It isn't legal advice. **Unverified** marks what couldn't be read in a primary source.

**COPPA** [63][64][65]:
- **Dates:** the amended rule was published in April 2025, and compliance has been due since **22 April 2026** [63].
- **"Directed to children":** decided by factors that include subject matter, visual content and animated characters [64].
- **Mixed-audience services** must age-screen neutrally before collecting personal information, and must not block children [64][65].
- **What an under-13 can do without verifiable parental consent:** only a persistent identifier used for *support for internal operations*, with notice. That covers keeping user-driven state such as scores or character choices [64][65].
- **Push:** the device information used for push counts as online contact information. So push to an under-13 needs consent, or the narrow multiple-contact exception, which requires notifying a parent [65].
- **Names:** a first name or nickname combined with an identifier is personal information [64].
- **Paperwork:** the 2025 rule adds a written retention policy (§ 312.10) and a written security program (§ 312.8) [64].
- **Age-checking data:** the FTC's February 2026 policy statement won't pursue data collected solely to determine age, if it's deleted promptly and used for nothing else [66].
- The FTC declined to finalize limits on push and engagement techniques, but said it remains concerned about them [78].

**Apple:**
- **Guidelines:** 5.1.4 (kids' data, and no metadata implying kids are the audience) and 1.3 (Kids Category) [30].
- **Age ratings:** new 13+, 16+ and 18+ ratings, with an age-assurance question, required from 31 January 2026 [67].
- **Declared Age Range (iOS 26):** returns a band, never a birthdate. Parents control sharing. Apple says to check age where the law requires it [68].
- **The Significant Change API** (PermissionKit) handles parental approval for significant updates in states with app-store laws [68].
- **Sign in with Apple and children:** Apple has said Sign in with Apple doesn't support under-13 accounts (a 2020 staff reply, and current status is unverified) [73].
- **Third-party logins:** 4.8 requires a privacy-preserving login option alongside them. Sign in with Apple already satisfies it for future providers [30].

**App-store age laws:**
- **Texas SB 2420** has applied to new Texas accounts since 4 June 2026, with the merits appeal pending [70][71].
- **Utah and Louisiana:** Apple shares age categories there, though the statute dates conflict [72].
- **California's AB 1043** from 2027 has developers request an age signal (secondary).
- **Developer duties:** rate the app, use the store's signals only for age limits and safety defaults, and take significant changes through the store [70].

**UK and EU:**
- **The ICO Children's Code,** standard 13, says no nudges that lead children to share more or weaken privacy [74]. Standard 5 treats "sticky" features (reward loops, notifications) as an impact-weighing test (secondary).
- **The EU's DSA Article 28 guidelines (July 2025)** recommend that features driving excessive use, streaks and push among them, be off by default for minors, with no push in core sleep hours [76]. They target online platforms, which Pounce likely isn't (unverified).
- **GDPR Article 8:** the age of consent is 13 to 16, by member state [75].

**New York SAFE for Kids:** no notifications to under-18s from midnight to 6 a.m. without parental consent, effective 25 January 2027, for feed-based platforms [77].

*Taken:* §14.1.

## 5. The recommendation on one page

- **The unit is the pair** **(JD)**.
  - Any two people who each take a turn in the same game form a pair, and each pair has one streak: JD and his wife, JD and his son, JD and his mom.
  - Home, the widgets and the reminders lead with your top pair.
- **A day is kept when both of you played together** **(JD)**.
  - Each of you takes at least one turn in a game you share.
  - Days are counted in each person's own time zone and roll over at 4 a.m.
  - Turn-based play has one fairness problem: you can't play when the move isn't yours. Two rules cover it:
    - **The late move pass.** If the move only reached you in the last two hours before your quiet hours, or later, you're covered for today.
    - **Held days.** At a family table, if a third person held the move all day, the day neither counts nor breaks.
  - So a day is only ever missed when someone held the move earlier in the day and didn't play. The app never says who that was.
- **Forgiveness is built in and free.**
  - The pair shares up to two **cat naps**, which cover a missed day automatically.
  - With no nap left, a **win-back** starts: keep the next two days and the streak returns whole.
  - Either of you can **pause** it for up to 14 days **(JD)**.
  - After a real break, the best streak and lifetime days together stay on show, and the next Monday brings a fresh deal.
- **Accounts make it one you on every device** **(JD)**.
  - Everyone is a **player** from first launch.
  - Sign-in identities attach to a player: Apple now, other providers later through one interface.
  - A guest keeps a full streak. Signing in is an **anonymous upgrade** (same player, nothing moves). Signing in on a second device merges that device in.
  - Seats, tables, the archive, streaks, rewards and settings belong to the player and sync.
  - Kids follow the rules for minors (§14.1).
- **Pounce: "come play with me."**
  - Tap someone's cat, then pick a table to make a move at, a new game, or "you pick", and they get a push with your cat on it.
  - It also works as a link in Messages.
  - It's rate-limited, and "not now" is respected.
- **Rewards come in three layers:**
  - a shared **Cat Condo** that grows with lifetime days together and never shrinks;
  - a **gift box** at each streak milestone, holding a card back, a rug or a toy;
  - a **toy** that drops onto the condo every kept day.
  - All are cosmetic, earned only by playing together, and never sold.
  - **Anyone at a table can change its rug and card back** **(JD)**.
- **Notifications are few and warm.**
  - "Mia played. Your move at Couch Cats."
  - One daily reminder, at your learned time or a time you set.
  - A last-chance reminder in the evening.
  - Pounces.
  - Adjustable quiet hours, during which pushes land silently.
  - At most two reminders a day, backing off after missed days and stopping after a week.
- **Widgets and a Live Activity.**
  - The small widget shows the two cats on the condo, the streak numeral and today's two paws.
  - The medium widget adds your tables and a Pounce button.
  - Lock screen widgets and StandBy carry the same state.
  - **Live table** is a Live Activity that appears when you leave a game the other person is actively playing. It shows whose move it is, updates by push, and ends itself after 30 minutes with no move or at the end of the round. You can swipe it away or turn it off **(JD)**.
- **The server owns the truth.**
  - `Player` Durable Objects hold accounts, devices, tables, settings and reminder clocks.
  - `Pair` Durable Objects hold the streaks.
  - `GameRoom` seats belong to players and report every completed turn.
- **The order.** It ships in eight PRs after this doc: accounts (server, then app) → streaks (server, then app) → notifications and Pounce → widgets → Live Activity → reward art (§15).

## 6. What counts as "playing today"

### 6.1 Definitions **(JD rule, call details)**

- **Shared table:** a room in `playing` status where both people of the pair hold a human seat. A seat on the same phone counts too, so pass-and-play on the couch counts. Bot seats are ignored. Any Pounce game counts, so future games will too.
- **Turn:** a completed turn by a human seat, ended by that seat's own action. In Cat Tower that's a discard or going out. Drawing alone doesn't count, and a turn taken by a bot never counts.
- **Player:** a signed-in account, or a guest person (§13.1).
- **Pair:** two players who have each completed at least one turn at the same shared table. It lasts until either of them leaves it (§14). Kids, parents and partners are all pairs alike **(JD)**.
- **Day:** each player's local calendar day, rolling over at **04:00** local time. A turn at 1 a.m. counts as "tonight". The day of a turn is computed in the time zone of the person who took it.
- **Evening cutoff:** two hours before that person's quiet hours start. With the default quiet hours, that's 20:00.
- **In for the day:** a person is in for day `D` if either:
  1. they completed a turn at a shared table during `D`; or
  2. they were **waiting**: at no moment between the start of `D` and their evening cutoff did they hold the move at a shared table **(JD: the two-hour window is right)**. That is, the move never reached them, or it reached them only after the cutoff. This is the **late move pass**.
- **Kept day:** both people are in, and at least one of them actually took a turn.
- **Held day:** neither person took a turn, there was a shared table in play all day, and neither of them held the move before their cutoff, because a third human held it all day. This happens only at family tables. A held day neither grows nor breaks the streak, and it shows as a plain day **(call)**.
- **Missed day:** anything else, unless the pair is paused.
- **Streak count:** kept days in a row, including today once it's kept. Nap, held and paused days don't add to it but don't break the run. During the day the count shows yesterday's total until today is kept, then goes up by one at once: the "extend" moment.

### 6.2 Why this rule **(JD, research)**

JD chose "both of us playing together" **(JD)**. It's also the Duolingo friend-streak rule: both of you do a lesson each day. Learners with a friend streak complete their daily lesson 22% more often (§4.1).

In a turn-based game, a pure "both play every day" rule is unfair in one way. If your partner holds the move all day and plays at 11 p.m., you could lose a day you never had the chance to play. The late move pass fixes that without hiding anything:

- In a two-person game, a day is missed only when someone held the move during the day and didn't take it.
- The app never says who that was. Settled days show only kept, nap, held or paused, and the status pushes name nobody.
- A nap or the win-back usually absorbs the miss first.

Both of you can still work out whose move it was, because "your move" is shown all day. Hiding that would break the game's turn cue, so this design accepts it. That fits the research too: Silverman & Barasch found that what hurts after a break is self-blame and having no repair (§4.5). The design never assigns blame, and it always offers repair.

**What "together" means in practice:**
- Each of you makes at least one move in a game you share. That can be "just a few moves" **(JD)**.
- Cat Tower turns affect each other: discards feed the other player's hand, and hits land on their laid groups.
- A future co-op game counts the same way.

### 6.3 Time zones and the day boundary **(call)**

- Each device reports its IANA time zone (`TimeZone.current.identifier`):
  - on launch;
  - on foreground;
  - on `NSSystemTimeZoneDidChange`.
- A player's time zone is the most recently reported one from any of their devices.
- **Day key:** the `YYYY-MM-DD` of `(instant − 4h)` in that zone. The Worker computes it with `Intl.DateTimeFormat`, so DST is handled. A DST day is simply 23 or 25 hours long.
- **Settlement:** a pair's day `D` settles once *both* players' day `D` has ended, plus 10 minutes. The `Pair` sets an alarm for that moment. Until then, today's state is live.
- **Travel:**
  - A day that had both turns is kept, whatever the clock did.
  - A flight that eats most of a day is what naps are for.
- **Fallback zone:** a player with no time zone yet uses their partner's zone, then `America/Los_Angeles`.

## 7. One shared streak per pair **(JD, call)**

- **Every pair that plays together gets a streak** **(JD)**:
  - JD and his wife, his son, his daughter, his mom;
  - and his wife and his mom, if those two play together.
- **No personal streak.** A personal streak would reward playing alone (bots), and the point is together. Duolingo's lesson is also that the streak works because it's one number you care about (§4.1).
- **Not per table.** Tables end, so a streak tied to one would die with every game. The pair is what lasts.
- **Your top pair** is the pair shown first everywhere: the one with the longest current streak, with the most recent turn breaking ties. You can pin another, from the Us screen and in the widget's configuration.
- **Same-phone pairs.** Two people playing pass-and-play on one phone are an ordinary pair. On a signed-in phone, the household people belong to that account (§13.1).

## 8. Naps, win-back, pause and fresh start

### 8.1 Cat naps (streak freeze) **(call, research)**

- **One shared pool per pair, at most 2.** Duolingo found that holding two raised daily actives without adding days off (§4.1). A shared pool means a nap is never "yours" or "mine".
- **Earned:**
  - 1 at the 7-day milestone;
  - 1 for each perfect week: seven kept days in a row with no naps. Duolingo's perfect week rewards a week kept without freezes [5].
  - Naps are never bought.
- **Applied automatically** at settlement to a missed day.
  - The day shows a cat asleep under a blanket.
  - The next morning both of you get a quiet push: "A cat nap covered yesterday. 12 days and counting."
- **Effect on the count:** it doesn't go up on a nap day, but the run continues.

### 8.2 Win-back (repair) **(call, research)**

- **When it starts:** a day is missed and no nap is left. The streak doesn't drop to 0. It goes into **win-back**:
  - the numeral wears a bandage;
  - two empty paw dots show beside it, so the progress starts endowed (§4.4).
- **Success:** keep the next two days and the streak comes back whole. The missed day becomes a nap day, and the count carries on.
- **Failure:** if either of those days is missed, the streak ends at 0. A kept day among them starts the new streak.
- **Free, earned by coming back.** Milkman et al. found that rewarding the return after a miss worked best (§4.5). Duolingo charges for repair, and deceptive.design lists that as a dark pattern [56].

### 8.3 Pause **(JD)**

- **Up to 14 days at a time** **(JD)**. Either person can pause from the Us screen, using a suitcase and a day dial.
- **While paused:** days neither grow nor break the streak, and the pair gets no reminders. Pounces and "your move" still work.
- **Extending and ending:** pausing again extends the pause, up to 14 days from today. Either person can end it early.
- **Both people see it:** the suitcase shows on the badge and the widget. The other person gets a quiet push: "JD put the cats to bed for 3 days."

### 8.4 When a streak ends: the fresh start **(call, research)**

- **What stays:**
  - The count goes to 0, but **best streak** and **days together** (lifetime kept days) stay big on the Us screen.
  - The Cat Condo never shrinks (§9.1).
- **No "streak lost" screen.** The condo cats are curled up asleep, and the fresh 0 has a soft sparkle that invites a new run.
- **Fresh-start push:**
  - When: the next Monday or the 1st of the month, whichever comes first, and only if the pair hasn't already started again.
  - What: each person gets one push at their reminder time: "New week, new deal. One turn starts a streak with Mia." This uses the fresh start effect (§4.5).
  - It's sent once per break.

## 9. Milestones and rewards

Every reward is cosmetic or a celebration, earned only by playing together, never sold, and never needed to play **(call, research)**.

### 9.1 The Cat Condo (the thing that grows) **(call)**

The condo is the pair's shared cat tree, with your two cats sitting on it. It's the hero of the Us screen and the small widget. It grows a stage at **lifetime days-together** thresholds, which never go down, so a broken streak never takes away what you built. Only the streak numeral resets.

| Stage | Lifetime days together | Added |
|---|---|---|
| 1 | 1 | a round cushion on the rug |
| 2 | 3 | a scratching post |
| 3 | 7 | the first platform |
| 4 | 14 | a hammock |
| 5 | 30 | a second tier and a dangling yarn toy |
| 6 | 50 | a tunnel |
| 7 | 100 | a tower top with the crown |
| 8 | 150 | a window perch with a moon |
| 9 | 200 | string lights |
| 10 | 365 | a glowing rooftop deck and fireworks |

**Why a condo, not a cat that grows:**
- The cats are each person's avatar, drawn as whole-cat sprites: 8 cats × 7 poses **(app)**. Levelling them would mean regenerating 56 consistent sprites per level.
- A condo needs one illustration per stage. Each stage is generated with the previous stage as an extra `-i` reference, the same way the cat pose sets were kept consistent.

### 9.2 Streak milestones and gift boxes **(call, research)**

- **Milestones:** 3, 7, 14, 30, 50, 75, 100, 150, 200, 250, 300 and 365, then every 100. They're quick early and widen later (goal gradient, §4.4).
- **Progress arc:** the Us screen always shows the distance to the next milestone as an arc that starts part-filled.
- **The gift:** each milestone hands both people the same gift box, a glossy box tied with magenta yarn. The server decides the content. Each person unwraps their own.
- **Content (variable):** the server picks something the pair doesn't own yet, from a tier set by the milestone.
  - Small milestones (3, 14, 50, …): a toy or a card back.
  - Big milestones (7, 30, 100, 365): a rug or a rare card back, plus a nap at 7.
  - Once everything is owned, gifts give toys and confetti.
- **Repeats:** milestones give again each time they're reached, so a fresh start gets quick wins at 3 and 7.
- **Where gifts open:** on Home or the Us screen, never mid-table.

### 9.3 Toys (the daily surprise) **(call, research)**

- **When a toy drops:** one toy drops onto the condo on every **kept day**, at the moment the second person's turn completes the day.
  - The person who completed the day sees it live.
  - The other person sees it at their next open.
- **The set:** 24 toys, among them a yarn ball, feather wand, cardboard box, mouse, fish, bell, laser dot and catnip sack.
- **Rarity:** 16 common, 6 shiny and 2 golden.
- **Keeping the set finishable:**
  - no duplicates until the set is complete;
  - a shiny at least every 7 kept days;
  - a golden at least every 30.
- **Never spendable or tradable** (§4.5 on variable rewards versus gambling).
- **A full set** unlocks the golden yarn card back.

### 9.4 Card backs and rugs, changeable by anyone at the table **(JD, call)**

- **Card backs:** the default violet paw, plus 6 to unlock: yarn swirl, moonlit fish, cucumber chaos, crown, heart paws and golden yarn.
- **Rugs:** the default magenta, teal and orange rug, plus 4 to unlock: night sky, candy stripe, fish pond and royal violet.
- **Anyone seated at a table can change its rug or card back at any time, as in a group chat** **(JD)**. The control is in the table menu: a rug icon opens a tray of rug and back tiles.
- **What you can pick from:** what *you* have unlocked with anyone **(JD)**. Changing the table shows off your rewards.
- **How it shows:**
  - Everyone at the table sees the change at once.
  - A little pill floats down with the changer's cat and the new rug or back. There are no words.
  - The rug cross-fades. Card backs swap on the next draw animation.
- **Rate limit:** one change per person every 10 seconds, so two people can't strobe it.
- **Server:**
  - New client message `{ t: "setLook", rug?, back? }`, accepted from any seated human.
  - The ids are validated against the known catalog. Ownership isn't checked, because it's cosmetic and the tray only offers what you own.
  - New event `{ kind: "look", seat, rug, back }`.
  - `look` is stored on the room. Older rooms get the defaults.
- **A new table** starts with the creator's last-used look.

### 9.5 Celebrations **(call)**

- **Day kept** (your turn completed today for both of you):
  - The table's streak badge does a double paw *stamp*, and the numeral rolls up by one.
  - Sparkle with `sfx-sparkle`, a haptic, and the toy arcs to the corner.
  - It lasts under a second and never blocks play.
- **Your half done** (you're in, and the other person isn't yet): one paw lights up, with a small stamp.
- **Milestone:** the gift waits on Home. Opening it is full screen:
  - The box wiggles, then bursts.
  - The reward spins in on a sunburst, reusing `Celebrations.swift`.
  - Both cats strike their `celebrate` pose.
- **Condo stage:** the new piece drops in with squash and stretch, and the cats leap onto it.
- **Reduce Motion:** fades instead of arcs, and no shake.

### 9.6 Art list (Codex pipeline, placeholders first) **(call)**

New prompt files go under `Art/prompts/habit/`, in the house style of `push-priming.txt`:
- `condo-1` … `condo-10`
- `toy-*` (24)
- `back-*` (6)
- `rug-*` (4)
- `gift-box` (closed and open)
- `paw-badge` states: grey, one paw, both paws, nap blanket, bandage, suitcase
- `pounce-bell`: a cat ringing a bell at a doorway, for the Pounce push and the Messages card
- `cats-asleep-condo`: for StandBy and night
- `live-table` assets, reusing the cats and a mini rug

JD approves in three batches:
1. badge states, the gift box, the pounce bell and condo 1–5;
2. toys;
3. backs, rugs and condo 6–10.

## 10. In-app surfaces

### 10.1 Home **(call)**

- **Streak badge:** the two paws plus the numeral, at top center by the hero. It's live for your top pair. A tap opens the **Us screen**.
- **Table tiles:**
  - They keep their "your turn" bell.
  - A table where your turn would **complete today** gets a small paw on its corner.
- **The people row** (the owner's corner today): your pairs' cats appear beside your own cat. Tapping a cat opens **Pounce** (§12.4).

### 10.2 The Us screen (new) **(call)**

- **The Cat Condo:** both cats, the toys scattered on it, and the big numeral.
- **Three stat tiles:** **best**, **days together** and **perfect weeks**, each a numeral with an icon.
- **This week's strip:** seven paw dots, each grey, kept, nap, held or suitcase. It never shows who played.
- **The next-milestone arc,** plus any unopened gift boxes.
- **Round buttons:** **Pounce** (a bell), **pause** (a suitcase) and **settings** (a gear, §12.6).
- **Several pairs:** a row of cats at the top switches between them. Long-press a cat to pin it as your top pair, or to leave that streak (§14).
- **No shared table in play:** a big **Play** pill appears. It runs Pounce with "new game" preselected.

### 10.3 Table top bar **(call)**

When both people of a pair are seated at this table, a small streak badge for that pair sits here. If several pairs are seated (family tables), it shows the top one. This badge is where the stamp plays.

### 10.4 "Play again" **(call)**

`GameOverView` gets a **Play again** pill.

- **Server message:** `{ t: "rematch" }`, available to any seated human once the room is `over`, and accepted once per room.
- **What it creates:** a new room with the same name and look.
  - Seats are filled straight from the old room's seats: the same player for humans, the same bots.
  - It **deals at once**, with no lobby, because a lobby would let someone who never opens the app stall the new table.
  - The first seat rotates.
- **Who is told:**
  - Everyone in the old room gets `rematch: <newCode>`.
  - Everyone else gets "Mia dealt a new game."
  - Whoever holds the first move also gets "your move".
- **The tables list:** the old room's entry points to the new one.

This closes the parent iOS spec's server follow-up #2.

### 10.5 Accounts in the app **(JD, call)**

- **Never required.** Pick your cat works as today, and play starts at once as a guest.
- **Sign-in offers** show the provider buttons. In v1 that's only **Sign in with Apple**; later providers appear as more buttons in the same spot. They're offered:
  - on the people sheet;
  - on the gear sheet;
  - when a streak first reaches 3, as a little cloud with a plus on the Us badge, meaning "keep this on all your devices";
  - when a second device of yours shows up. That's detectable only when you're signed in, so before then the offer comes from the people sheet.
  - Never to a player under 13 (§14.1).
- **Signing in:**
  - On a guest phone, the anonymous upgrade runs in place.
  - On a second device, it merges into your player. That device then shows your cat, name, seats and tables.
- **A household person** can sign in on their own: hold their cat on the people sheet.
- **The gear sheet** shows:
  - the account (your cat with a check);
  - linked providers (icons);
  - sign out;
  - **delete account** (§14).

## 11. Widgets

**Target and sharing:**
- The `PounceWidgets` target, bundle `com.conleychaos.play.widgets`, holds the widgets and the Live Activity.
- It shares an **App Group** (`group.com.conleychaos.play`) for the snapshot and the art.
- It shares a **keychain access group** for the device credential, which its intents need **(call)**.

### 11.1 Widget set

| Widget | Family | Shows | Tap / action |
|---|---|---|---|
| **Us** | `systemSmall` | The condo with both cats (pose by state), the numeral, and today's two paws. Each paw lights when that person is in. | Opens the table where it's your move, otherwise the Us screen. |
| **Us + tables** | `systemMedium` | Left: the small widget. Right: up to 2 shared tables, each with the table name and either your bell ("your move") or their cat ("their move"). Below: a round **Pounce** button. | A row opens that table. **Pounce** (an interactive `AppIntent`) sends a pounce to the pair's partner with target "you pick", then shows a check until it's answered or the hour passes (§12.4). |
| **Streak** | `accessoryCircular` | The paw ring with the numeral. The ring fills halfway or fully for today. | Opens the Us screen. |
| **Us** | `accessoryRectangular` | The partner's cat (template-rendered), the numeral, and a bell when it's your move. | Opens your move. |
| **Inline** | `accessoryInline` | The paw image plus "12 · Mia". | Opens the app. |
| **StandBy** | `systemSmall` in StandBy | Night art: both cats asleep on the condo with the numeral. Red in night mode. | — |

**Cat poses by state:**
- **Your move, today not done:** your cat awake, theirs looking at you.
- **Their move:** your cat idle, theirs awake.
- **Your half done:** your cat celebrating.
- **Kept:** both cats celebrating.
- **Paused:** both asleep.
- **Win-back:** a bandage on the numeral.

The poses reuse the existing cat sprites **(app)**. Interactive buttons work only on an unlocked device [35].

**Configuration:** a `WidgetConfigurationIntent` with one parameter, *partner*. It defaults to your top pair and lists partners by name and cat.

**Rendering:** glass, tinted and clear home screens. In accented and vibrant modes, the cats and condo use mono template versions, and the numeral is `widgetAccentable` [33][34].

### 11.2 Freshness **(call, research)**

WidgetKit allows about 40 to 70 reloads a day [36]. Freshness comes from five sources:

- **Timeline entries** for predictable changes, with no network needed:
  - the 4 a.m. rollover (today goes back to grey);
  - the end of a pause;
  - the evening "at risk" pose.
- **The app** writes the snapshot to the App Group and calls `WidgetCenter.reloadTimelines`:
  - whenever it fetches streaks;
  - once more when it goes to the background [38].
  - Foreground reloads don't use up the budget [36].
- **The Notification Service Extension:** every alert push carries the `streak` block (§12.7). The extension writes it to the App Group and reloads.
  - *Verify on device in PR 7 that a reload from the extension takes effect. The widget push covers it if not.*
- **WidgetKit push** [37]:
  - The widget extension adopts `WidgetPushHandler`, and `pushTokenDidChange` uploads the token (`PUT /v1/devices/me/widget-push`).
  - The server sends:
    - `apns-push-type: widgets`;
    - topic `com.conleychaos.play.push-type.widgets`;
    - body `{"aps":{"content-changed":true}}`;
    - `apns-priority: 5`.
  - It sends one when the widget state changes *without* an alert to that device. Examples: the other person's half landed while it isn't your move, settlement at rollover, a pause, or a pounce answered.
  - **Server throttle:** one per device every 15 minutes [34].
  - The push carries no data, so the provider makes one short `GET /v1/me/streaks` (5-second timeout) and falls back to the App Group snapshot.
- **Server truth** wins on the next app open.

### 11.3 Live table (Live Activity) **(JD, call, research)**

Cat Tower games run for days, longer than a Live Activity may last (8 hours active, 12 at most [40]). Apple also says Live Activities are for events with a clear start and end [42]. So the Live Activity covers a **live stretch of play**, not the whole game.

**When it starts** (the server starts it with **push-to-start** [41], so it doesn't depend on the app winning a race while going to the background):
- you leave the app, or lock the phone, at a table where the game is `playing` and at least one other human is `awake` there right now; or
- you answer "Play" to a pounce and then leave the app before the table is done.
- At most one live table at a time per device. A newer one replaces the older.

**What it shows:**
- **Lock screen:** the rug strip with every seat's cat; whose move it is (a glowing ring on that cat, and a bell when it's yours); each player's phase numeral; the table name; and the pair's streak paws.
- **Dynamic Island:**
  - Compact: your cat on the leading side; the bell, or the current player's cat, on the trailing side.
  - Minimal: the bell, or the current player's cat.
  - Expanded: the lock screen layout, condensed.
- **No buttons.** A tap opens the table. Apple recommends at most one control, and opening the table is the only useful one.

**How it updates:**
- `GameRoom` sends `apns-push-type: liveactivity` updates (`event: update`, `content-state`) on each turn change, and on round end with `event: end`.
- Priority is 5, except when the move comes to you: that update uses priority 10 with an `alert`, so the lock screen lights up and plays the turn sound.
- While a live table is running for a table, the regular "your move" notification for that table is suppressed. The HIG says not to duplicate the Live Activity with notifications [42].
- Update tokens arrive through `pushTokenUpdates`, and the app uploads them (`PUT /v1/devices/me/live-activity`). *Verify in PR 8 that the app gets background time to upload the token after a push-to-start. Before then, the fallback is the regular "your move" notifications.*

**How it ends (hides itself, JD):**
- `event: end` with `dismissal-date` = now when:
  - the round or game ends;
  - you return to that table in the app;
  - **30 minutes pass with no move at the table**.
- `stale-date` is set to last update + 30 minutes, so a missed push still greys it out.
- **A hard cap of 2 hours** per activity.
- You can always swipe it away on the lock screen **(platform)**.
- The gear sheet has a **live table** toggle, as the HIG asks [42]. It's on by default.
- The game isn't "live" when the other person is away, so it doesn't start then.

## 12. Notifications

### 12.1 The set **(call)**

| Kind | When | To | Interruption | Cap |
|---|---|---|---|---|
| **Your move** (exists, new copy) | The move reaches you, and none of your devices is awake in that room (and no live table is running for it). | The player whose move it is, on all of their devices. | `active`, or `passive` in quiet hours | Once per turn (exists), collapsed per table (exists) |
| **Daily reminder** | At your reminder time (§12.3), only when all of these hold: today isn't kept for your top pair; you aren't in yet; it's your move at a shared table; and you haven't opened the app in the last 2 hours. | You. | `active` | 1 a day |
| **Last chance** | 90 minutes before your quiet hours, if the streak is 3 or more, you aren't in, and it's your move. On by default, one toggle turns it off. Duolingo's first big streak win was its late-night streak saver [10]. | You. | `active` (not Time Sensitive, §12.5) | 1 a day, part of the 2 |
| **Pounce** | Someone pounces on you (§12.4). | You. | `active` communication notification; `passive` in quiet hours | §12.4 limits |
| **Pounce answered** | They tapped Play, In a bit, or Not now. | The sender. | `passive` | — |
| **Nap used**, **win-back**, **paused** | At settlement, or when a pause starts. | Both. | `passive` | — |
| **Milestone** | A milestone was reached and you weren't in the app. | Both. | `active` | — |
| **Play again** | A rematch was dealt. | The others. | `active` | — |
| **Fresh start** | The first Monday or 1st of the month after a break (§8.4). | Each person, at their reminder time. | `active` | Once per break |

**Age bands change the defaults:** kittens get no server pushes at all, and teens get gentler defaults and no overnight sends (§14.1).

**Hard caps,** which the `Player` DO enforces:
- **Reminder-type pushes:** at most 2 a day. These are the daily reminder, last chance and fresh start. "Your move" and Pounce aren't counted: one is the game, and the other is a person asking.
- **Spacing:** at most one push of any kind every 20 minutes, except "your move" and Pounce.
- **Quiet hours:** reminders never go out. Everything else is sent `passive`.

### 12.2 Copy **(call)**

The voice is the cats: warm, a little dramatic about *themselves*, never about the other person. Copy names people but never blames them. No emoji, no countdowns, no guilt. The title stays the name of the person the push is for, which matters on shared phones **(app)**.

| Kind | Title | Body (rotated, no repeat within 7 days) |
|---|---|---|
| Your move | JD | "Mia played. Your move at Couch Cats." / "Mia played. Your turn makes today count." (the second when your turn would complete today) |
| Daily reminder | JD | "The cats are on the rug. Your move at Couch Cats." / "Day 13 is up for grabs. One turn with Mia keeps it." / "Mia's cat is guarding the deck. Your move." / "A turn with Mia, then the couch." |
| Last chance | JD | "One turn tonight keeps 12 days going." / "The cats want one more turn before bed." |
| Pounce: a table | JD | "Mia wants to play. Couch Cats?" |
| Pounce: new game | JD | "Mia wants to play. New game?" |
| Pounce: you pick | JD | "Mia wants to play. You pick." |
| Pounce answered | Mia | "JD is coming." / "JD: in a bit." / "JD: not now." |
| Nap used | Couch Cats | "A cat nap covered yesterday. 12 days and counting." |
| Win-back | Couch Cats | "Two days in a row brings 12 back." |
| Paused | Couch Cats | "Mia put the cats to bed for 3 days." |
| Milestone | Couch Cats | "30 days together. There's a gift on the rug." |
| Play again | Couch Cats | "Mia dealt a new game." |
| Fresh start | JD | "New week, new deal. One turn starts a streak with Mia." |
| Last reminder before going quiet (§12.3) | JD | "The cats will keep your seat warm." |

**Never written:**
- "Mia is waiting on you"
- "Don't break your streak"
- "You missed yesterday"
- anything with a timer
- anything to one person about the other's absence

For streak pushes, the title is the table's name when the pair has one shared table, and the partner's name otherwise.

### 12.3 Timing, backoff and quiet hours **(JD: adjustable; call, research)**

**Reminder time is adjustable** **(JD)**, with two choices:
- **Auto (the default):**
  - The `Player` DO keeps a histogram of the local time of your **first turn each day**, in 30-minute buckets, with weekdays and weekends kept separate. Each day the old weights decay by ×0.85, so recent habits count most.
  - The reminder fires 15 minutes before the weighted median.
  - Until there are 5 days of data, it uses **19:30** local **(JD: "that timing is fine")**.
  - This is the simple form of Duolingo's lesson: send near when the person usually practices (§4.1).
- **A fixed time:** one for weekdays and one for weekends.

**Either way, the reminder time is clamped:**
- outside quiet hours;
- at least 2 hours before quiet hours start.

**Copy rotation** is round-robin. A bandit like Duolingo's needs far more users than a family TestFlight.

**Quiet hours are adjustable** **(JD)**:
- The default is 22:00 to 08:00 local **(JD)**.
- They're set per player and synced.
- During quiet hours, reminders never go out, and every other push lands `passive`: silent, in Notification Center.

**Backoff** (counted in days you took no turn at any shared table):
- After 2 days: no last chance.
- After 4 days: the daily reminder comes only every other day.
- After 7 days: one "The cats will keep your seat warm.", then no reminders at all.
- Your next turn resets the backoff.
- Pounces still work during backoff (§12.4 has its own limits).

### 12.4 Pounce: "come play with me" **(JD, call)**

**The moment:** you sit down with someone, the TV's on, and you want them to come play **(JD)**.

**Starting a pounce.** You start one from any of these:
- a cat in Home's people row;
- the Us screen's bell;
- the medium widget's button;
- a long-press on a table tile;
- the share sheet.

A sheet opens with the other person's cat at the top. You pick a target from three big picture tiles, with no words beyond table names:
1. **A table you share.** "Come make a move." Their-move tables come first, and they're preselected when there is one.
2. **New game.** A plus on a rug. When it's answered, the server deals a new Cat Tower table seating you both (and nobody else), with your last-used look.
3. **You pick.** Dice. They choose from your shared tables or a new game.

**Sending it:**
- **To someone who already plays with you** (has a player): a push. It's a **communication notification** with your cat as the avatar (§12.5), category `POUNCE`, and actions **Play** (`.foreground`), **In a bit** (background) and **Not now** (background).
  - Opening it lands on the table they picked, or on the "pick one" sheet.
  - The new-game table is created at that moment.
- **Through Messages** (or anywhere else):
  - The sheet's share button sends a link: `https://play.conleychaos.com/p/<token>`.
  - Its preview card shows your cat ringing the pounce bell, plus your name.
  - With the app installed, the link opens the same "pick one" sheet.
  - Without it, it opens the existing TestFlight landing page **(server)**.
  - This is how you pounce on someone who doesn't play yet (a new pair). On "new game" they're seated as a guest straight from the link.
- **Answering:**
  - Play: the sender sees their cat sprint in, and gets "JD is coming."
  - In a bit: shows a little clock, and sends "JD: in a bit."
  - Not now: shows a sleeping cat, and sends "JD: not now."

**Limits** (no nagging, §4.5):
- at most **3 pounces an hour** from one person to another;
- after **Not now**, no pounces from that sender for 1 hour;
- after **3 unanswered in a row**, the pounce button rests for 3 hours and shows a sleeping bell.

**In quiet hours** the pounce lands silently, and the sender sees a moon on it ("they may be asleep"). **iOS Focus decides beyond that (JD).** Communication notifications from people the recipient has allowed through a Focus can still break through, under iOS's own control [24]. Pounce has no "always ring" override.

**Pounce link tokens:**
- 16 random bytes, single use.
- They expire after 24 hours.
- They're stored in the sender's `Player` DO and looked up through a small `Links` index (§13.3).

### 12.5 iOS specifics **(call, research)**

- **Authorization:**
  - The existing priming and system prompt stay **(app)**.
  - **New:** "Not now" on priming requests **provisional** authorization, which shows no prompt. Reminders then arrive quietly in Notification Center with iOS's own Keep / Turn Off buttons [22].
  - Home's bell still offers the full prompt once.
- **Interruption levels:**
  - `active`: your move, reminders, last chance, pounce, milestone, play again.
  - `passive`: status pushes, and anything in quiet hours.
  - **No Time Sensitive.** A card game isn't urgent, and using it would spend trust [24].
- **Grouping:**
  - `thread-id`:
    - the room code for table pushes (exists);
    - `pair:<pairId>` for streak pushes;
    - `pounce:<senderPlayer>` for pounces.
  - No `summary-arg`: iOS ignores it since iOS 15 [26].
  - Collapse id: the room code for "your move" (exists), and `<kind>:<id>` for the others, at most 64 bytes [27].
  - `relevance-score`: your move 1.0, pounce 0.9, reminders 0.6, status 0.2.
- **Badge:** `aps.badge` is the number of tables where it's your move. The app sets the same number on refresh.
- **Across devices** (§13): "your move" goes to all of a player's devices. When you play from one device, the server sends the others a background push (`content-available: 1`, no alert). Their app removes that table's delivered notifications and updates the badge. It's best effort: iOS may delay background pushes.
- **Categories and actions:**
  - `YOUR_MOVE` and `REMINDER`:
    - **Play** (`.foreground`, opens the table): the lock screen "take your turn".
    - **In an hour** (background): schedules a local reminder, with no server call.
  - `POUNCE`: **Play**, **In a bit** and **Not now**. The background actions `POST` the answer inside `beginBackgroundTask`, with an idempotency id, and retry on the next launch [28].
  - `STATUS`: none.
- **Notification Service Extension** (`PounceNotify`, `com.conleychaos.play.notify`), triggered by `mutable-content: 1`:
  - It makes pushes from a person (your move, pounce, play again) into **communication notifications**. That's an `INSendMessageIntent` whose sender `INPerson` has the sender's cat face from the shared art as the avatar [24]. This needs the Communication Notifications capability.
  - It writes the payload's `streak` block to the App Group and reloads the widgets.

### 12.6 Settings (synced) **(JD, call)**

The gear sheet and the Us screen's gear share one panel, in pictures and numerals:
- a bell toggle for reminders ("your move" is unaffected);
- reminder time: an **Auto** chip, or two clock dials (weekdays and weekends);
- quiet hours: moon and sun dials;
- a last-chance toggle;
- a live table toggle.

The settings belong to the player, so they sync across devices.

### 12.7 Payload additions **(call)**

```json
{
  "aps": {
    "alert": {"title": "JD", "body": "Mia played. Your move at Couch Cats."},
    "sound": "default", "thread-id": "GH2VD", "mutable-content": 1,
    "category": "YOUR_MOVE", "interruption-level": "active", "relevance-score": 1.0, "badge": 2
  },
  "code": "GH2VD",
  "kind": "your_move",
  "from": {"name": "Mia", "cat": 2},
  "streak": {"pair": "p_3f9c…", "count": 12, "me": false, "them": true, "naps": 1, "myMove": ["GH2VD"], "theirMove": []}
}
```

It's about 400 bytes, well under the 4 KB APNs limit.

## 13. Server design

### 13.1 Identity: players, identities and the anonymous upgrade **(JD, call)**

JD wants accounts that sync everything, and other sign-in providers later **(JD)**. Signing in must never be required: a guest keeps a streak and can bring it along when they sign in **(JD)**. The design separates **who you are** (a player) from **how you prove it** (identities).

**Players**
- A **player** is one person: their name and cat, seats, tables, streaks, rewards and settings.
- `playerId` = `"p_"` + 16 random bytes, base64url.
  - It's **never derived from a provider's user id**.
  - Seats, pairs, tables and pounces refer only to `playerId`. So providers can be added, removed or swapped later without re-keying anything.
- **Everyone is a player from the first launch.** Pick your cat creates the person on the phone, as today. The first `PUT /v1/devices/me/profile` creates a **guest player** for each person on the phone. "Guest" only means the player has no sign-in identity yet. A guest has the same streaks, rewards and seats as anyone else.

**Identities**
- An identity is a verified claim, "this is player X".
- The single `Identities` index DO maps `(provider, subject_hash) → playerId`, where `subject_hash = SHA-256(provider + ":" + subject)`. Raw provider subjects aren't stored.
- Each provider is a server module with this interface:

  ```ts
  type IdentityProvider = {
    id: "device" | "apple" | "google" | "email" | "passkey";
    verify(proof: unknown, env: Env): Promise<{ subject: string; secret?: string } | null>;
    revoke?(secret: string, env: Env): Promise<void>; // called on unlink and account deletion
  };
  ```

  Adding a provider later means a new module, a button in the app, and a row in this table. No data migrations.

| Provider | v1? | Proof | Notes |
|---|---|---|---|
| `device` | yes | person id + `personKey` (32 random bytes kept in the Keychain; the server stores its hash, trusting it on first use) | The guest credential. Every person has one. It binds a guest player to the phone(s) holding the key. Person ids are visible at a table, so the key, not the id, is what proves it. |
| `apple` | yes | identity token + nonce, and the authorization code (§4.6) | Requests no scopes (no email, no name). The refresh token is stored as the identity's `secret`, used only by `revoke` (below). |
| `google`, `email` (one-time code), `passkey` (WebAuthn) | later | per provider | Same interface. For email, the address hash is the subject. A passkey needs the server's own WebAuthn verification, with no third party. |

**Sessions are ours, not the provider's.**
- The existing device credential, an HMAC device token **(server)**, stays the only session.
- Signing in **links this device to a player**: `DeviceIndex.player_id` and `Player.devices`.
- Provider tokens are never used as sessions. A provider outage or a provider being dropped logs nobody out, and an Android client later can reuse the same device-credential scheme.

**The anonymous upgrade.** When you sign in with a provider on a device, one of two things happens:
1. **The identity is new: it attaches to your guest player in place.**
   - The `playerId` stays the same, so nothing moves.
   - Streaks, seats, tables, rewards and settings are already yours. Your partner sees no change.
   - This is the common case: you sign in for the first time.
2. **The identity already belongs to another player:** for example, you signed in on your iPhone first, and now on the iPad. The device's guest player **merges** into that player (rules below):
   - its `device` identity re-points to that player;
   - it's left as a forwarding stub for 30 days, so any reference that's in flight still resolves.

**Linking, unlinking, signing out:**
- **Link another provider:** `POST /v1/me/identities/{provider}`, for example adding Google to an Apple-signed player later. If that identity already belongs to a *different* player, the app shows the two cats merging into one, and merges only on a yes.
- **Unlink:** allowed when another sign-in identity remains. Unlinking the last one turns the player back into a guest on this device, with the data kept.
- **Sign out:** this device unlinks and starts a fresh guest player. The account and its data stay with the account, ready for the next sign-in.

**Household people** (pass-and-play on one phone):
- Each person is their own guest player, bound to the phone by its own `device` identity.
- On a signed-in phone, they're listed on the owner's account, so they follow the owner to the iPad.
- Any of them can upgrade on their own later, from the people sheet: hold their cat, then sign in. For example, a kid who gets their own Apple Account.
  - That runs the same anonymous upgrade for *that* player.
  - Their streak with Dad comes along.
- (§14.1 has the rules for minors.)

**Seats belong to players.**
- `SeatInfo` gains `playerId` for every human seat, guests included.
- **Control:** a device controls a seat when the device is linked to the seat's player, or holds that guest player's `device` identity.
  - The Worker resolves both and passes them to the room in a new internal header, `x-play-player`, alongside `x-play-device`. Both are stripped from client requests, as today.
  - `RoomCore.controlledSeats(deviceId)` becomes `controlledSeats(deviceId, playerIds)`.
- **Existing rooms:** seats without a `playerId` keep today's `deviceId` rule. The first profile upload sends `adopt(personId → playerId)` to each of the device's rooms, which backfills them.
- **Presence:** a seat is `awake` if any of its player's devices is awake in the room.

**Merge rules** (`Player.merge(fromId)`):
- **Tables:** every room where `from` holds a seat gets `adopt(from → to)`.
- **Pairs:** each pair of `from` re-points to `to`. If `to` already has a pair with the same partner, the two merge:
  - the longer current streak wins;
  - lifetime counters take the maximum;
  - toys and unlocks are unioned;
  - naps take the maximum, capped at 2.
- **Name and cat:** the target player keeps its own.
- **Settings:** last writer wins per key.

**What syncs:** everything on the player:
- name and cat;
- household people;
- seats and tables (through rooms);
- the archive;
- tutorial progress;
- settings: sound, haptics, pace, reminder time, quiet hours, last chance, live table;
- streaks and rewards;
- the last-used table look.

**Device-only:** push tokens, the time zone report, and cached snapshots.

**Apple's revocation key, and why it's not needed yet:**
- Verifying a Sign in with Apple token needs no secret, only Apple's public keys (§4.6).
- Only `revoke` needs one: a client secret signed with a Sign in with Apple private key, which is used to exchange the authorization code at sign-in and to revoke on deletion.
- The design makes that key **optional**, exactly like the APNs key today (`ci.yml` warns and turns push off when `PLAY_API_APNS_KEY_P8` is unset) **(server)**:
  - **Without `PLAY_API_SIWA_KEY_P8` / `PLAY_API_SIWA_KEY_ID`:** sign-in works, and no refresh token is stored. Account deletion deletes all data and shows, as a picture, the iOS path for stopping Apple sign-in for the app: Settings → your name → Sign in with Apple → Pounce. That's Apple's documented fallback when an app holds no tokens [61].
  - **With the key** (needed before App Store submission): codes are exchanged and tokens revoked automatically.
  - **One key for both:** a single new key with both *Apple Push Notifications service* and *Sign in with Apple* enabled can back both pairs of secrets (§4.6 search: one key may carry several services). That's one visit to the portal, once.

### 13.2 Durable Objects **(call)**

**`DeviceIndex`** (exists, one per device) gains:
- `player_id`, set when signed in;
- `time_zone`;
- the push tokens: APNs (exists), widget, Live Activity push-to-start, and per-activity update tokens.

Its push path:
- `push(intent)` picks `active` or `passive` from the player's quiet hours;
- adds the `streak` block, `badge`, `category` and `mutable-content`;
- forgets dead tokens, as today.

Tables for guest devices stay here, as today.

**`Player`** (new, one per `playerId`):
- **`meta`:** name, cat, `age_band` (§14.1), and `forward_to` (merged stubs).
- **`identities(provider, subject_hash, secret, linked_at)`:** mirrors the `Identities` index for this player. `secret` holds only what a provider's `revoke` needs, such as the Apple refresh token.
- **`devices(device_id, attached_at, last_seen)`**
- **`people(person_id, name, cat)`:** household people (accounts only).
- **`settings`:** a single JSON row, last writer wins per key, with `updated_at` per key.
- **`tables`:** the same shape as today's `DeviceIndex.tables`. `GameRoom` reports seats that have a `playerId` here.
- **`archive(code)`** and **`tutorial(key, value)`**.
- **`pairs(pair_id, partner_id, pinned)`** and **`left(partner_id)`:** tombstones (§14).
- **`playtime(bucket, daytype, weight)`:** 48 × 2 buckets.
- **`reminders`:** today's key, `sent_today`, `last_sent_at`, `backoff_days`, `last_turn_day`, the copy rotation, and `fresh_start_sent_for`.
- **`pounces(id, to, target, created_at, answered)`** plus the limit counters, and **`links(token, pounce_id, expires)`**.
- **An alarm** at the next reminder decision. It asks its pairs for `today()`, decides by §12.1 and §12.3, and pushes through each device's `DeviceIndex`.

**`Pair`** (new). It's named by a random `pairId` (16 bytes, base64url) made when the pair forms, and both players store it.
- **`people(player_id, name, cat)`:** two rows.
- **`streak`:** a single row with `count`, `run_started_day`, `last_settled_day`, `best`, `lifetime_kept`, `perfect_weeks`, `perfect_run`, `naps`, `winback_from_day`, `winback_kept`, `paused_until_day`, `paused_by` and `break_id`.
- **`days(day PRIMARY KEY, turns_a, turns_b, held_before_cutoff_a, held_before_cutoff_b, state)`:**
  - `state` is one of `live`, `kept`, `nap`, `held`, `paused`, `missed` or `winback`.
  - It never records whose miss a day was, and the API never exposes per-person rows for past days.
  - 120 days are kept, plus the lifetime counters.
- **`moves(code PRIMARY KEY, holder_id, since)`** and the active shared tables.
- **`rewards`:**
  - `owned(item_id, got_at)`;
  - `gifts(gift_id, milestone, item_id, opened_a, opened_b)`;
  - `toys_pity(shiny_since, golden_since)`.
- **An alarm** at the next settlement (§6.3).

**`Identities`** (new, a single instance; it can be sharded by hash prefix if it ever needs to be): `identities(provider, subject_hash PRIMARY KEY, player_id)`.

**`Links`** (new, a single instance): `token → (playerId, expires)` for pounce links. Rows are deleted when used or when they expire.

**`GameRoom`** (exists) gains:
- `playerId` on seats, plus `adopt`;
- `look`, with `setLook`;
- `rematch`;
- turn reporting to pairs;
- moving-the-move updates;
- Live Activity pushes (start, update, end);
- background "dismiss" pushes to a player's other devices;
- new-game creation for pounces.

The game logic stays in `RoomCore`.

### 13.3 Flows **(call)**

1. **Turn completes** (`RoomCore` emits `turn` for the next seat):
   - If the seat that finished is human, a `StreakIntent {by, at, code, next}` is drained beside the push intents.
   - For each other human player `p` at the table, `GameRoom.after()` calls `Pair(by, p).turn(...)`, using `waitUntil` with one retry. A failure is logged, never fatal: a lost update is cosmetic, and the game is saved.
   - The pair computes today's key and updates `days` and `moves`, settling any days that are past due first.
   - If this turn makes both people in for today, the day is kept at once: the count goes up and a toy is drawn.
   - It returns a `StreakView`, which the room sends to the two players' sockets as `{ t: "streak", pair, view }`. That's additive: the iOS socket already skips unknown messages **(app)**.
   - The mover's `Player` records the playtime bucket.
2. **Move arrives** (`next` is a pair member):
   - `moves` is updated. If it's before that person's cutoff, `held_before_cutoff` is set for today.
   - "Your move" goes out with the new copy, or a Live Activity update when one is live.
   - The player's other devices get the dismiss push for that table's earlier notifications.
3. **Settlement alarm** (`Pair`): for each unsettled day, the first rule that applies sets its state:
   1. paused;
   2. kept (both in);
   3. held;
   4. a nap, if one is left;
   5. otherwise win-back, or a reset.

   Then it updates milestones, gifts, perfect weeks and naps, asks both `Player`s for any status push, and re-arms.
4. **Pounce:** `POST /v1/pounces` checks the limits, stores the pounce, and pushes it or returns a link token. The answer comes from `POST /v1/pounces/{id}/answer`.
   - "New game", or "you pick" answered with a new game: the Worker creates a room seating both players. For a link answered by a guest, that's the link opener's device. Then it deals.
5. **Reminder alarm** (`Player`): decides at the reminder time and at the last-chance time, then re-arms for tomorrow.
6. **Room ends or closes:** pairs drop that room from `moves`, and `Player` and `DeviceIndex` tables are updated, as today.

### 13.4 HTTP API **(call)**

All routes use device-token auth, as today. The routes under `/v1/me/...` act for the device's player: the account if signed in, otherwise the person named in the body.

| Method and path | Body → result | Notes |
|---|---|---|
| `POST /v1/identities/{provider}` | `{proof, person: {id, key}}` → `{playerId, upgraded \| merged, profile}` | Sign in for that person on this device: the anonymous upgrade, or a merge (§13.1). `provider` is `apple` in v1. |
| `POST /v1/me/identities/{provider}` | `{proof, confirmMerge?}` → `{linked}` or `409 {otherPlayer: {name, cat}}` | Link another provider. A 409 asks the app to confirm a merge. |
| `DELETE /v1/me/identities/{provider}` | → 204 | Unlink. |
| `POST /v1/me/signout` | → 204 | Unlinks this device. The device keeps playing as a fresh guest. |
| `DELETE /v1/me` | → 204 | Deletes the player and all their data (§14). |
| `PUT /v1/devices/me/profile` | `{timeZone, people: [{id, name, cat, key}]}` → 204 | Called on launch and on a time zone change. Binds guests. The existing 1 KB body cap rises to 2 KB for this route. |
| `GET /v1/me/state` / `PATCH /v1/me/state` | `{settings, people, archive, tutorial}`, per-key `updatedAt` | Sync. A patch merges last writer wins per key. |
| `GET /v1/devices/me/tables` (exists) | | Returns the player's tables when signed in. |
| `GET /v1/me/streaks` | `{pairs: [StreakView]}` | `StreakView` = `{pair, partner: {name, cat}, count, me, them, naps, winback, pausedUntil, best, lifetimeKept, perfectWeeks, week: [7], next, condoStage, toys, unlocked, gifts, myMove, theirMove, pounce: {sent, resting}}` |
| `PUT /v1/pairs/{pair}/pause` | `{days: 1-14}` → 204 | |
| `DELETE /v1/pairs/{pair}/pause` | → 204 | Ends a pause early. |
| `POST /v1/pairs/{pair}/gifts/{id}/open` | → 204 | |
| `PUT /v1/pairs/{pair}/pin` | → 204 | Pins this pair as your top pair. |
| `DELETE /v1/pairs/{pair}` | → 204 | Leave (§14). |
| `POST /v1/pounces` | `{to?: playerId, target: {table: code} \| "new" \| "pick"}` → `{id, link?}` | With `to`, a push. Without it, a link. |
| `POST /v1/pounces/{id}/answer` | `{answer: "play" \| "later" \| "no", choice?: code \| "new"}` → `{code?}` | |
| `GET /p/{token}` | HTML preview page (OG card) | Public. Same pattern as `/j/<CODE>` **(server)**, and added to AASA. |
| `PUT /v1/devices/me/widget-push` | `{token}` → 204 | From the widget extension. |
| `PUT /v1/devices/me/live-activity` | `{pushToStart?, activities?: [{code, token}]}` → 204 | |

**WebSocket additions:**
- server messages `{t:"streak"}` and `rematch`;
- client messages `{t:"rematch"}` and `{t:"setLook"}`;
- the `look` event.

`PROTOCOL_VERSION` stays 1. These are additive, and the client skips unknown messages **(app)**.

### 13.5 Limits and costs **(call)**

- A `Pair` wakes about once per turn and once a day.
- A `Player` wakes up to 3 times a day.
- Live Activity pushes are one per turn, only during live play.

At family scale, all of this is a rounding error on Durable Objects pricing.

## 14. Privacy

**What's new on the server:**
- **Identities:** a hash of each provider's user id. When the optional Apple key is set, also the Sign in with Apple refresh token, kept only to revoke it. No email, and no Apple name.
- **Age band:** kitten, teen or adult (§14.1). Never a birthdate.
- **Per device:** the time zone.
- **Per player:** settings, a histogram of the times of day you start playing, the tables list, the archive and tutorial flags.
- **Per pair:** daily state for 120 days, lifetime counters and rewards.
- **Pounces:** kept 7 days.

**Never collected:** location (the time zone is enough), contacts, ad identifiers, analytics, or phone numbers. Messages pounces go through the system share sheet, and Pounce never reads your contacts.

**Who sees what:**
- **The other person in a pair** sees the pair's state: the count, today's two paws, the week strip, rewards and gifts.
- **Nobody** sees your playtime histogram or your settings, or a record of who played on past days.
- **Today's paws** are visible to both of you, because they're what tells you it's your move. After settlement, only the day's outcome remains.

**Lock screen:** pushes show names and table names, as today **(app)**. iOS's Show Previews setting hides them.

**Leaving a streak:**
- Where: on the Us screen, long-press the cat, then the trash can.
- It deletes the `Pair` and its history for both of you. The other person sees it disappear, with no push.
- It sticks: the leaver's `Player` keeps a tombstone, so the pair doesn't re-form the next time you play.
- Only the leaver can undo it: a ghosted cat with a plus in the Us screen's row starts a fresh pair at 0 **(call)**.

**Deleting your account** (gear sheet, then account, then the trash can, with a confirm; required by App Review 5.1.1(v) [30]):
- It deletes the `Player`.
- It leaves every pair.
- It revokes each identity's tokens through the provider's `revoke`, when the key is configured. Without the key, it shows the Settings path for stopping Apple sign-in (§13.1) [61].
- Rooms keep your seat, but it falls back to the device that last held it. The game goes on, and nothing breaks for the others.

**Retention:**
- day rows: 120 days;
- guest `Player`s with no device for 90 days: deleted;
- merged guest stubs: 30 days;
- pounce links: 24 hours.

**Logging:** no player ids, pair ids, tokens or names in logs. Invocation logs stay off **(server)**.

**App Store privacy:**
- `PrivacyInfo.xcprivacy` keeps the existing User ID and Device ID declarations.
- It adds **Product Interaction** (play times) and **Other Usage Data** (streak state), for App Functionality only, with no tracking.
- The App Store Connect privacy label needs the same update before external TestFlight review.

### 14.1 Minors **(JD: "follow all the rules for minors"; research §4.7; call)**

*This is a design that follows the rules as researched, not legal advice. JD should have counsel review §14.1 before the App Store launch (§17).*

**Audience: mixed, not child-directed.**
- Pounce is for couples and families: adults, with their kids and parents. Children aren't the primary audience.
- Bright cartoon cats are a COPPA "directed to children" factor [64]. So the app's metadata, screenshots and copy must present it as a couples-and-family game, never a kids' app.
- It stays out of the Kids Category (Apple 5.1.4 and 1.3) [30].
- The App Store age-rating questionnaire is answered truthfully, with "Age Assurance: yes" [67].
- As a mixed-audience service, the app **must age-screen before collecting personal information, and must not block children** [64][65].

**Three age bands.** The server stores only the band, never a birthdate:

| Band | Ages | Shown as |
|---|---|---|
| `kitten` | under 13 | a kitten |
| `teen` | 13–17 | a young cat |
| `adult` | 18+ | a grown cat |

**How the band is set:**
- **The phone's owner,** at first launch, before anything is sent to the server:
  1. The app asks the **Declared Age Range** API (iOS 26) for ranges split at 13 and 18 [68]. This is the age signal the Texas, Utah and Louisiana app-store laws, and California's AB 1043 from 2027, expect developers to use. Apple says to check age where the law requires it [68][70][71][72].
  2. If the person declines to share, or the API returns nothing, the app shows a **neutral age screen**. It's a numeral keypad (the room-code keypad's style) for the birth year:
     - there's no default value and no hint about what's "allowed";
     - the result goes into the Keychain, so the back button can't retry it;
     - the year is turned into a band on the device and then discarded [65].
  3. The FTC's February 2026 policy statement covers data collected only to work out age, as long as it's deleted promptly and used only for that [66].
- **Household people** (pass-and-play): the parent who adds someone taps kitten, young cat or grown cat. That's an adult declaring for a family member. Whether data a parent enters on their own phone counts as "collected from a child" is unsettled, so the design treats a parent-entered kitten exactly like a child [65] (unverified).
- **Re-checks:** the band is checked again with Declared Age Range on each launch, at most once a week. If Apple reports a newer band (a kitten turned 13), the limits lift. That's when the anonymous upgrade lets them sign in and keep their streaks.

**Under 13 (`kitten`), with no parental consent (v1).** COPPA allows only a persistent identifier used for support for internal operations, with notice [64]:

| Area | What's allowed |
|---|---|
| **Play** | Full games, seats and turns. The device id and seats are internal operations. |
| **Streaks and rewards** | Yes. Streaks, rewards and the condo are game progress, which the FAQ counts as internal operations ("scores, character choices") [65]. The partner (Dad) sees the pair's streak, as with anyone. |
| **Name** | **Generated, not typed.** The kitten picks one from the existing `NameGenerator` list (Mochi, Biscuit, Pickle…) with the dice. There's no free-text field, because a name plus an identifier is personal information [64]. The cat avatar is chosen as usual. |
| **Push notifications** | **None from the server.** No "your move", reminders, pounces, milestones, widget pushes or push-started Live Activities. The FTC treats a push token as online contact information [65]. The narrow multiple-contact exception needs parent notice, which v1 has no way to give. Local, on-device reminders only: the existing 10-minute turn reminder, and a daily one at a fixed 17:00, both off by default. Nothing is sent anywhere. |
| **Learned timing** | Off. There's no play-time histogram for kittens: no profiling. |
| **Sign-in** | Not offered. Apple has said Sign in with Apple doesn't support under-13 accounts [73], and an account would collect more. |
| **Pounce** | A kitten can **send** in-app pounces to people they already play with. Nothing is collected from them, and the push goes to the adult. They can't **receive** pushed pounces. They see waiting pounces in the app and on the widget's next refresh. |
| **Messages links** | None: no share-sheet links out from a kitten's device. |
| **Widgets** | Yes, refreshed by timelines and by the app only. No widget push. |
| **Live table** | No push-to-start or push updates. |
| **Retention** | The kitten's player is deleted after 90 days with no activity. Pair history is capped at 120 days, as for everyone. |

**Later: parent consent (PR 9, §15).** This lets a kitten on their own device get turn pushes and pounces from family.
- A **signed-in adult player** gives verifiable parental consent from their own device, using one of the COPPA methods, e.g. "email plus" or "text plus" [64].
  - That needs the parent's email. It's collected for this purpose only, and §13.1 still requests no Apple scopes.
- The kitten's device is linked to that parent.
- What it unlocks: turn pushes, pounces from the people the parent approves, and a fixed-time reminder. Learned timing stays off.
- Apple's PermissionKit "ask to communicate" is the alternative to evaluate when building it [69].
- The consent can be revoked at any time.

Until then, **a kitten's best setup is as a household person on a parent's phone or iPad.** Pushes then go to the parent's device, titled with the kitten's generated name, and the parent hands over the phone. That's exactly how pass-and-play works today.

**13 to 17 (`teen`).** Everything is available, with gentler defaults (DSA Article 28 guidelines and the ICO Children's Code [76][74]; best practice, since Pounce is likely outside the DSA's "online platform" scope):
- **Off by default, and the teen can turn them on:** daily reminders, the last-chance push, and learned timing. A fixed reminder time is offered instead.
- **"Your move" pushes and pounces stay on.** They're a person or the game, not engagement nudges.
- **Quiet hours:** default 21:00–08:00. **Nothing is ever sent between 00:00 and 06:00**, not even `passive`. That mirrors the New York SAFE for Kids Act's overnight rule, though that act targets feed-based platforms [77].
- **No nudges to weaken privacy.** No prompts to sign in, share links or turn on reminders beyond the one in-context offer (ICO standard 13) [74].
- **Sign in with Apple is allowed.**

**Everyone.** Features that already follow the ethics line in §4.5 and §12:
- no ads, analytics, location or third-party SDKs;
- no free-text messaging;
- invites by code or link only;
- no strangers, and no public profiles.

**Paperwork.** COPPA's 2025 rule applies in full from 22 April 2026 [63]. PR 2 adds these, drafted for JD and counsel to review:
- `docs/privacy/retention-policy.md`: written retention, as § 312.10 requires;
- `docs/privacy/security-program.md`: a written security program with a named coordinator and an annual review (§ 312.8);
- the privacy policy and COPPA direct notice at `play.conleychaos.com/privacy`, linked from the gear sheet (§ 312.4(d), Apple 5.1.4) [64][30].

**State app-store acts.**
- **Texas SB 2420** is in force for new Texas accounts from 4 June 2026, with an appeal pending [71].
- **Utah and Louisiana** have dates that conflict between Apple and the statutes [72].

What they require of developers:
- The developer rates the app, uses the store's age and consent signals only for age limits and safety defaults, and treats "significant changes" through the store [70].
- **This work is a significant change:** accounts, new data (play times, streaks) and new notifications. So the release with PR 2 goes through Apple's **Significant Change API** (PermissionKit), letting a parent approve for a minor in those states [68].

**GDPR (if Pounce goes worldwide).**
- Pounce relies on contract and legitimate interest, not consent, for play.
- Wherever consent is the basis (optional reminders and learned timing for a teen), Article 8's age of consent applies: 13 to 16 depending on the member state [75].
- The simple rule: in the EU, a teen's optional reminders and learned timing stay off unless the teen turns them on, which the defaults above already do.

## 15. Phasing into shippable PRs

Each PR ships to TestFlight on its own and leaves the app working **(call)**.

| # | PR | Contents | Depends on |
|---|---|---|---|
| 0 | **This design** | The doc. | — |
| 1 | **Server: players and identities** | The `Player` and `Identities` DOs; guest players from profile upload; the provider interface with `device` and `apple`, where Apple verification needs no secret and the code exchange and revocation run only when the optional key is set; the anonymous upgrade and merge; link and unlink; device link; seats by `playerId`, with `controlledSeats(deviceId, playerIds)` and the `x-play-player` header; `adopt`; tables per player; `/v1/me/state` sync; sign-out and deletion; all-device pushes and dismiss pushes; age bands (§14.1). Tests. | 0 |
| 2 | **App: accounts, sync and age** | Sign-in offers (§10.5) with Sign in with Apple; the anonymous upgrade and merge confirm; household sign-in; settings, people, archive and tutorial synced; the tables list from the player; badge clearing across devices; the Declared Age Range request and the under-13 limits (§14.1); deletion UI. | 1 |
| 3 | **Server: streaks** | The `Pair` DO; turn reporting; the both-in rule with the late move pass and held days; settlement; naps, win-back and pause; milestones, gifts and toys; the streak routes; `{t:"streak"}`; `rematch`; `setLook` and `look`. Fake-clock tests across time zones, DST and the rollover. A `STREAKS` env var stays off in production until PR 4 ships. | 1 |
| 4 | **App: streak UI, Play again, table looks** | Home badge; the Us screen; the stamp; gifts; pause; leave; pin; Play again; the table menu's look tray, with default looks and **placeholder** unlocks. | 2, 3 |
| 5 | **Notifications and Pounce** | Server: reminder alarms (auto and fixed time), caps, backoff, quiet hours, status, milestone and fresh-start pushes, the new copy, and pounces with links, `/p/` pages and the OG card. App: categories and actions, provisional, the synced settings panel, the Pounce sheet and answer flow, and the share link. The `PounceNotify` extension with communication avatars. | 3, 4 |
| 6 | **Widgets** | The `PounceWidgets` target, App Group and keychain group; small, medium, the three accessory families and StandBy; configuration; the interactive Pounce intent; timelines; reloads; WidgetKit push. | 4 (5 for push refresh) |
| 7 | **Live table** | The Live Activity in §11.3: push-to-start, updates and end from `GameRoom`; the 30-minute and 2-hour limits; the toggle. | 5, 6 |
| 8 | **Reward art** | Codex art in three approval batches (§9.6), which swaps in for placeholders by file name. It can start in parallel any time after PR 4. | 4 |
| 9 | **Parent consent for kittens (later)** | Verifiable parental consent from a signed-in adult, which unlocks turn pushes and approved pounces for an under-13 on their own device (§14.1). Build it only if the kids play on their own devices. | 5 |

**Why this order:**
- Accounts come first, because streaks key on players. Keying them on guest identity first would mean a migration later.
- Streaks become visible (4) before they can nag (5).
- Widgets and the Live Activity build on the notification plumbing.
- Art runs alongside, placeholders first **(JD)**.

## 16. Testing **(call)**

- **Server (vitest, as today):**
  - Settlement tables for one and two time zones, DST, and turns at 03:59 and 04:01.
  - The late move pass at the cutoff edge.
  - Held days at three-person tables.
  - Naps (used and earned), perfect weeks, win-back (success and failure) and pause up to 14 days.
  - Milestones and gift content (seeded), and toy pity.
  - Reminder decisions under caps, backoff, quiet hours, and fixed and auto times.
  - Pounce limits and link tokens.
  - Sign in with Apple token verification, against fixture keys and tokens, never real ones.
  - Guest merges, including two guest pairs with the same partner.
  - Seat control by player, and `setLook` and `rematch`.
- **App (PounceKit tests):**
  - decoding `StreakStore`, `MeState` and the settings merge;
  - badge state mapping;
  - widget snapshots;
  - the `PushPolicy` additions.
- **UI tests:**
  - the Us screen from `DemoFixtures`;
  - the stamp after a turn on the dev server;
  - Play again;
  - the look tray;
  - Pounce sheet targets;
  - sign-in from a stubbed provider in Debug.
- **Widgets and the Live Activity:** Xcode previews for every family, state and rendering mode.
- **Age bands:**
  - Declared Age Range results are stubbed in Debug.
  - A neutral age screen can't be retried.
  - Kitten limits are enforced on the server: no push of any kind to a kitten's devices, and no histogram.
  - Teen defaults, and the 00:00–06:00 block.
- **Push and Live Activity delivery:** TestFlight builds only, since dev builds get sandbox tokens **(app)**. `MANUAL-CHECKLIST.md` gains the steps:
  - pounce from one phone to another;
  - pounce through Messages;
  - live table start, update, and end at 30 minutes;
  - iPad and iPhone in the same seat;
  - account deletion.

## 17. Open questions only JD can answer

JD answered rounds 1 and 2 on 2026-11-04, marked **(JD)** throughout. Round 2 settled these:
- Guests keep streaks, and signing in is an anonymous upgrade.
- The two-hour late move pass.
- Table looks come from your own unlocks.
- Pounces follow iOS Focus, with no "always ring".

What's left:

1. **How old are your son and daughter, and do they have their own devices?**
   - Under 13 on their own device, they get **no server push** in v1: no turn pushes, pounces or reminders. That's required without parental consent (§14.1). They can still play, keep streaks with you, and get on-device reminders.
   - Playing as a household person on your phone or iPad gives the full experience today.
   - If they're under 13 and on their own devices, PR 9 (parent consent) moves up.
2. **Counsel review.** §14.1 follows the rules as researched, but it isn't legal advice. Before the App Store launch, not before family TestFlight, should a lawyer review it together with the privacy policy, the retention policy and the security program that PR 2 drafts?

**One action, needed only before App Store submission, not before PR 1:** create one key in the Apple Developer portal with both *Apple Push Notifications service* and *Sign in with Apple* enabled (primary App ID `com.conleychaos.play`). Then set it as the repo secrets, from the folder the key was downloaded to:

```bash
gh secret set PLAY_API_SIWA_KEY_P8 --repo jdconley/pounce < AuthKey_XXXXXXXXXX.p8
```

```bash
gh secret set PLAY_API_SIWA_KEY_ID --repo jdconley/pounce --body XXXXXXXXXX
```

The same key can replace the APNs pair (`PLAY_API_APNS_KEY_P8` and `PLAY_API_APNS_KEY_ID`) the same way. No session creates or handles the key; downloading a private key is outside what a session may do.

## 18. Left to the builder

- Exact animation timings, haptic patterns and sounds (start from `Juice.swift` and `Celebrations.swift`).
- The exact lineup of toys, card backs and rugs, and the prompt wording, within §9 (JD approves the art).
- `StreakView` fields beyond those listed; SQL schemas and indexes; migration tags.
- Medium widget layout on iPad and in StandBy; Live Activity layout details within §11.3.
- Further copy lines in the same voice (JD reviews them in the PR).
- Whether `Pair.turn` is called directly or batched per room `after()`.
- How the "pick one" sheet lays out its table tiles.

## Sources

Duolingo and couple or shared-streak apps:
1. Duolingo Blog, "Improving the streak" (2020). https://blog.duolingo.com/improving-the-streak
2. Duolingo Blog, "How Duolingo's streak builds habit." https://blog.duolingo.com/how-duolingo-streak-builds-habit
3. Duolingo Blog, "How to keep your streak on vacation" (2023). https://blog.duolingo.com/how-to-keep-your-streak-on-vacation/
4. Duolingo Blog, "How streaks keep Duolingo learners committed" (2017). https://blog.duolingo.com/how-streaks-keep-duolingo-learners-committed-to-their-language-goals/
5. Duolingo Blog, "Tips for maintaining your streak" (2022). https://blog.duolingo.com/tips-for-maintaining-streak
6. Duolingo Blog, "Protecting streaks from site issues." https://blog.duolingo.com/protecting-streaks-from-site-issues/
7. Duolingo Blog, "Friend Streak" (2024). https://blog.duolingo.com/friend-streak/
8. Duolingo Blog, "Friends Quests" (2022). https://blog.duolingo.com/friends-quests/
9. Duolingo Blog, "The Duolingo widget." https://blog.duolingo.com/widget-feature
10. J. Mazal, "How Duolingo reignited user growth," Lenny's Newsletter. https://lennysnewsletter.com/p/how-duolingo-reignited-user-growth
11. Lenny's Podcast with Jackson Shuttleworth, "Behind the product: Duolingo streaks" (2024). https://lennysnewsletter.com/p/behind-the-product-duolingo-streaks
12. K. Yancey, B. Settles, "A Sleeping, Recovering Bandit Algorithm for Optimizing Recurring Notifications," KDD 2020. https://research.duolingo.com/papers/yancey.kdd20.pdf
13. Gigazine (citing the Wall Street Journal) on Duolingo's reminders (2024). https://gigazine.net/gsc_news/en/20240618-duolingo-app-streaks
14. Duolingo Help Center, "What is a streak?" https://www.duolingo.com/help/what-is-a-streak
15. Snapchat Support, "How do Streaks work and when do they expire?" https://help.snapchat.com/hc/en-us/articles/7012394193684-How-do-Streaks-work-and-when-do-they-expire
16. Snapchat Support, "I lost my Streak. How do I restore it?" https://help.snapchat.com/hc/en-us/articles/7012318024852-I-lost-my-Streak-How-do-I-restore-it
17. EDRi and Bits of Freedom, Snapchat gamification survey (2026). https://edri.org/our-work/new-study-reveals-how-young-people-are-influenced-by-gamification-features-on-snapchat/
18. Paired Support, "What is a streak?" https://support.paired.com/en/articles/164646-what-is-a-streak
19. TechCrunch, "Locket … hits the top of the App Store" (2022). https://techcrunch.com/2022/01/11/locket-an-app-for-sharing-photos-to-friends-homescreens-hits-the-top-of-the-app-store
20. TechCrunch on Locket's growth (2025). https://techcrunch.com/2025/08/06/photo-sharing-app-locket-is-banking-on-a-new-celebrity-focused-feature-to-fuel-its-growth
21. unstar.app, couples-app review analysis (2026). https://unstar.app/blog/paired-lasting-love-nudge-evergreen-cupla-couples-apps-ranked-2026

Apple platform and notification practice:
22. Apple, "Asking permission to use notifications." https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications
23. Apple, `UNNotificationInterruptionLevel`. https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel
24. WWDC21 session 10091, "Send communication and Time Sensitive notifications." https://developer.apple.com/videos/play/wwdc2021/10091/
25. Apple, "Generating a remote notification." https://developer.apple.com/documentation/usernotifications/generating-a-remote-notification
26. Apple, `summaryArgument` (deprecated). https://developer.apple.com/documentation/usernotifications/unmutablenotificationcontent/summaryargument
27. Apple, "Sending notification requests to APNs." https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns
28. Apple, "Declaring your actionable notification types." https://developer.apple.com/documentation/usernotifications/declaring-your-actionable-notification-types
29. Apple, `UNNotificationServiceExtension`. https://developer.apple.com/documentation/usernotifications/unnotificationserviceextension
30. Apple, App Review Guidelines (4.5.3, 4.5.4, 5.1.2). https://developer.apple.com/app-store/review/guidelines/
31. Apple HIG, Notifications. https://developer.apple.com/design/human-interface-guidelines/notifications
32. Braze, Quiet hours. https://www.braze.com/docs/user_guide/messaging/messaging_fundamentals/quiet_hours
33. Apple HIG, Widgets. https://developer.apple.com/design/human-interface-guidelines/widgets
34. WWDC25 session 278, "What's new in widgets." https://developer.apple.com/videos/play/wwdc2025/278/
35. Apple, "Adding interactivity to widgets and Live Activities." https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities
36. Apple, "Keeping a widget up to date." https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date
37. Apple, "Updating widgets with WidgetKit push notifications." https://developer.apple.com/documentation/widgetkit/updating-widgets-with-widgetkit-push-notifications
38. WWDC26 session 277 (widgets). https://developer.apple.com/videos/play/wwdc2026/277/
39. WWDC26 session 345 (App Intents). https://developer.apple.com/videos/play/wwdc2026/345/
40. Apple, "Displaying live data with Live Activities." https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
41. Apple, "Starting and updating Live Activities with ActivityKit push notifications." https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications
42. Apple HIG, Live Activities. https://developer.apple.com/design/human-interface-guidelines/live-activities

Habit psychology, couples and ethics:
43. J. Silverman, A. Barasch, "On or Off Track: How (Broken) Streaks Affect Consumer Decisions," *Journal of Consumer Research* 49(6), 2023. https://udspace.udel.edu/handle/19716/34160
44. K. Milkman et al., "Megastudies improve the impact of applied behavioural science," *Nature* 600, 2021. https://authors.library.caltech.edu/records/mys88-cc756
45. P. Lally et al., "How are habits formed," *European Journal of Social Psychology*, 2010. https://doi.org/10.1002/ejsp.674
46. R. Kivetz, O. Urminsky, Y. Zheng, "The Goal-Gradient Hypothesis Resurrected," *Journal of Marketing Research* 43, 2006. https://business.columbia.edu/faculty/research/goal-gradient-hypothesis-resurrected-purchase-acceleration-illusionary-goal
47. J. Nunes, X. Drèze, "The Endowed Progress Effect," *Journal of Consumer Research*, 2006 (read via secondary summary). https://encyclopedia.pub/entry/38231
48. H. Dai, K. Milkman, J. Riis, "The Fresh Start Effect," *Management Science* 60(10), 2014. https://faculty.wharton.upenn.edu/wp-content/uploads/2014/06/Dai_Fresh_Start_2014_Mgmt_Sci.pdf
49. D. Kahneman, A. Tversky, "Prospect Theory," *Econometrica* 47(2), 1979. https://www.econometricsociety.org/publications/econometrica/1979/03/01/prospect-theory-analysis-decision-under-risk
50. E. Deci, R. Koestner, R. Ryan, "A meta-analytic review of experiments examining the effects of extrinsic rewards on intrinsic motivation," *Psychological Bulletin* 125(6), 1999.
51. D. Zendle, P. Cairns, "Video game loot boxes are linked to problem gambling," *PLOS ONE*, 2018. https://eprints.whiterose.ac.uk/139116/1/journal.pone.0206767.pdf
52. J. Driver, J. Gottman, "Daily marital interactions and positive affect during marital conflict," *Family Process* 43(3), 2004. https://pubmed.ncbi.nlm.nih.gov/15386956/
53. A. Aron et al., "Couples' shared participation in novel and arousing activities and experienced relationship quality," *JPSP* 78(2), 2000. https://pubmed.ncbi.nlm.nih.gov/10707334/
54. S. Coyne et al., "Gaming in the Game of Love," *Family Relations* 61, 2012. https://scholarsarchive.byu.edu/facpub/2340
55. M. Patel et al., BE FIT randomized trial, *JAMA Internal Medicine* 177(11), 2017. https://chibe.upenn.edu/publications/effect-of-a-game-based-intervention-designed-to-enhance-social-incentives-to-increase-physical-activity-among-families-the-be-fit-randomized-clinical-trial
56. deceptive.design on Duolingo's paid streak repair. https://www.deceptive.design/articles/when-a-user-uses-duolingo-on-a-series-of-consecutive-days-this-is-called-a-streak-if-users-miss-a-day-they-can-pay-to-repair-it
57. US FTC, *Bringing Dark Patterns to Light* (2022; read via a law-firm summary). https://www.arnoldporter.com/en/perspectives/advisories/2022/09/ftc-shines-a-little-light-on-dark-patterns
58. N. Eyal, Hook model and variable rewards (secondary). https://www.nirandfar.com/2012/03want-to-hook-your-users-drive-them-crazy.html
59. Deconstructor of Fun, Duolingo notification teardown (third party; unverified claims only). https://duolingo.deconstructoroffun.com/mechanics/notifications
60. WWDC20 session 10173, "Get the most out of Sign in with Apple," and the Apple Developer Forums thread on verifying the identity token. https://developer.apple.com/videos/play/wwdc2020/10173/ · https://developer.apple.com/forums/thread/124175
61. Apple Developer Forums, "About account deletion when users use Sign in with Apple." https://developer.apple.com/forums/thread/706792
62. WWDC22 session 10122, "Enhance your Sign in with Apple experience." https://developer.apple.com/videos/play/wwdc2022/10122/
63. Federal Register, COPPA Rule amendments (22 April 2025). https://www.govinfo.gov/content/pkg/FR-2025-04-22/html/2025-05904.htm
64. eCFR, 16 CFR Part 312 (COPPA Rule). https://www.ecfr.gov/current/title-16/chapter-I/subchapter-C/part-312
65. FTC, "Complying with COPPA: Frequently Asked Questions." https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions
66. FTC, COPPA policy statement on age verification (February 2026). https://www.ftc.gov/news-events/news/press-releases/2026/02/ftc-issues-coppa-policy-statement-incentivize-use-age-verification-technologies-protect-children
67. Apple Developer News, updated age ratings (July 2025). https://developer.apple.com/news/?id=ks775ehf
68. Apple, Age assurance (Declared Age Range, Significant Change API). https://developer.apple.com/support/age-assurance/
69. Apple, Kids and families (developer). https://developer.apple.com/kids/
70. Texas SB 2420, App Store Accountability Act (enrolled). https://capitol.texas.gov/tlodocs/89R/billtext/html/SB02420F.htm
71. Apple Developer News, Texas law update (June 2026). https://developer.apple.com/news/?id=sg176nne
72. Apple Developer News, Utah and Louisiana age categories. https://developer.apple.com/news/?id=f5zj08ey
73. Apple Developer Forums, Sign in with Apple and under-13 accounts (2020). https://developer.apple.com/forums/thread/134264
74. ICO, Age Appropriate Design Code, standard 13: nudge techniques. https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/childrens-information/childrens-code-guidance-and-resources/age-appropriate-design-a-code-of-practice-for-online-services/13-nudge-techniques/
75. GDPR Article 8. https://gdpr-info.eu/art-8-gdpr/
76. European Commission, guidelines on the protection of minors under DSA Article 28 (July 2025). https://digital-strategy.ec.europa.eu/en/library/commission-publishes-guidelines-protection-minors
77. New York Attorney General, final SAFE for Kids Act rules (July 2026). https://ag.ny.gov/press-release/2026/attorney-general-james-and-governor-hochul-release-final-safe-kids-act-rules
78. FTC press release, COPPA Rule changes finalized (January 2025). https://www.ftc.gov/news-events/news/press-releases/2025/01/ftc-finalizes-changes-childrens-privacy-rule-limiting-companies-ability-monetize-kids-data
