# Pounce daily habit loop ("Us" streak) — Design

Date: 2026-11-04 · Owner: JD Conley (Conley Chaos LLC) · Status: **draft, waiting on JD's approval**. Nothing gets built until JD approves.

Parent specs: `2026-10-31-pounce-cat-tower-design.md` (product and rules) and `2026-10-31-pounce-ios-design.md` (the client). Where this doc changes something they decided, it says so.

Marks: **(JD)** = JD's words or decision; **(call)** = a designer call made while writing this, open to override; **(research)** = follows from a cited source in §4; **(server)** / **(app)** = fixed by what is already built.

---

## 1. Intent

> "i want to play with my wife daily, so let's design something like duo lingo. a home widget that urges you to play something. push notifications to remind you to connect. streaks. rewards for those streaks. … i want this to be addictive, it's for a good cause." **(JD)**

Cat Tower is already a good game for two people who love each other. What it lacks is a reason to open it *today*. Async play makes this worse: a game can stall for days because nobody noticed it was their move. This design adds a daily loop on top of the game. A shared streak gives the reason. A home and lock screen widget makes it visible. Push reminders arrive at the time you usually play. Rewards are themed to the cats and celebrate the days you kept.

The aim is a habit in the Duolingo sense, with one difference that shapes every decision. **The streak belongs to the couple, and it must never become a way for one partner to feel bad about the other.** Sticky, yes. Guilt, blame or nagging, no. A relationship app that sours the relationship has failed even if its retention chart looks great.

**Success:** JD and his wife take at least one turn with each other on most days for two months (about how long a habit takes to form; Lally et al., §4.5). Both say the reminders feel like the cats asking them to play, not like the app scolding them.

## 2. Goals, non-goals, anti-goals

**Goals**
- A **shared streak per pair of people** ("Us"), kept by playing Cat Tower turns with each other. It is the one streak number in the app.
- **Forgiving by design:** automatic cat naps (freezes), a free way to earn a broken streak back, a pause for travel or illness, and a fresh-start moment after a break.
- **Rewards** that fit the Loud Toy art: a shared Cat Condo that grows, toys that drop on days you both played, card backs and rugs, and celebration moments.
- **Widgets:** home screen (small, medium), lock screen (circular, rectangular, inline) and StandBy. One interactive button, "send a paw", for when you are waiting on your partner.
- **Notifications:** the existing "your turn" push gets your partner's name. Add one daily reminder at the time you usually play, an optional last-chance reminder, partner paws, quiet hours, frequency caps and backoff.
- **"Play again"** with the same people when a game ends, so a finished game never stalls a streak.
- **Server:** pair and player state in Durable Objects, day boundaries in each person's own time zone, all settled on the server.

**Non-goals (this design)**
- A new mini-game. Taking turns at Cat Tower *is* the daily ritual (§6).
- Leagues, XP, leaderboards, or competition between couples. Pounce is not social with strangers (parent spec).
- Any purchase: no paid freezes, paid repair or gems. Pounce has no monetization (parent spec).
- Sign in with Apple and accounts. Those are still M2. This design works on today's device and person identity (§13.1).
- Analytics. Nothing leaves the server except to the two people in a pair.
- Android and the Mac.

**Anti-goals** (failure even if it "works")
- **Showing who broke it.** No screen, push or history entry ever says that one partner missed a day.
- **Confirmshaming or guilt copy.** No "Don't let Mia down" and no crying mascot.
- **Notifications at night**, or more than two reminders a day.
- **Countdown pressure:** no ticking timers and no "streak ends in 2h 13m".
- Rewards that feel like gambling: no loot boxes with currency and no paid rerolls.
- **Text on screen.** The no-words rule still holds: names, table names and numerals only, everything else art **(JD)**. Push copy is the one place for sentences, and it already has them **(app)**.
- **Emoji anywhere**, including push copy and widgets **(JD)**.
- Beige, muted, storybook art **(JD)**.

## 3. Constraints

- iOS 26+, iPhone and iPad, SwiftUI shell and SpriteKit table, Swift 6, Apple frameworks only, XcodeGen `project.yml` **(app)**.
- Bundle `com.conleychaos.play`, team `B222J9J7B8`. New targets need new bundle IDs under it, e.g. `com.conleychaos.play.widgets` and `com.conleychaos.play.notify` **(call)**.
- Server: Cloudflare Workers plus SQLite-backed Durable Objects (`GameRoom` per room, `DeviceIndex` per device). APNs is sent straight from the Worker with a `.p8` JWT (`src/push/apns.ts`) **(server)**.
- **Identity today:** a device has a `deviceId` and an HMAC token. People are created on the phone (`Person {id, name, cat}`, UUID made on device), and a phone can hold several (pass-and-play). Seats are claimed with a `Person`, and the server does not verify person ids **(server)**. This design builds on that; §13.1 covers its limits.
- The push path already in the app: priming (`PushPrimingView.swift`), `PushCoordinator` (token upload every launch, tap routing, the local 10-minute reminder), and the server `pushYourTurn` with `thread-id` and collapse id = room code **(app)**.
- Art comes from the Codex pipeline in `apps/play-ios/Art` with style reference `chosen-d-loud-toy.png`. Prompts are committed. **Placeholders come first and JD approves art in batches (JD).**
- Never touch the `:4343` server; work only in a worktree; no secrets in the repo (session rules).

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
  - *Taken:* one streak per pair (§7) and a partner paw (§12.4). The "both every day" rule is rejected for turn-based play (§6.2).
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
  - *Taken:* automatic naps and the earned win-back (§8). Paired avoids partner blame by splitting streaks. We avoid it with "either of you keeps the day", which keeps one shared number (§6.2).
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

## 5. The recommendation on one page

**The unit is the pair.** Any two people who have each taken a turn at the same table form a pair, and every pair has one streak. JD and his wife have one. JD and his mom would have another. Home, the widget and the reminders lead with your top pair.

**A day is kept when the game moved between you.** A day is kept when either of you takes a turn at a table you share. A day becomes a **together day** (a gold paw) when *both* of you took a turn. Days are counted in each person's own time zone, and the day rolls over at 4 a.m. In a two-person game the turns alternate, so the streak can only grow if each of you answers the other within about a day. Yet nobody can ever be blocked from keeping the day by a partner who holds the move: whoever holds the move is the one who can keep it. That is why this rule beats "both must play every day" (§6.2).

**Forgiveness is built in and free.** The pair shares up to two **cat naps**, which cover a missed day automatically. You earn them at 7 days and with each perfect week (seven together days). With no nap left, a miss starts a **win-back**: keep the next two days and the streak comes back whole. Either partner can **pause** the streak for a trip, an illness or a new baby. After a real break, the best streak and the lifetime count of days together stay on show, and the next Monday brings a "fresh deal" (fresh start effect, §4.5).

**Rewards come in three layers.**
1. A shared **Cat Condo** grows a stage at each lifetime milestone and never shrinks, even after a break.
2. A **gift box** opens at each streak milestone (3, 7, 14, 30, 50, 100, …). It holds a random card back, rug or toy that you don't have yet.
3. A **toy** drops onto the condo on every together day. It is a small surprise from a set of 24 to collect.

All three are cosmetic, earned only by playing together, and never sold.

**Notifications stay few and warm, and the timing is learned.**
- The existing "your turn" push now says who played: "Mia played. Your move at Couch Cats."
- One daily reminder goes out at the time you usually play, and only if today isn't kept yet and it's your move.
- A last-chance reminder comes in the evening, for streaks of 3 days or more. It's on by default, and one tap turns it off.
- A partner can send a paw at most once a day.
- Quiet hours default to 10 p.m. to 8 a.m. A push that lands during quiet hours is silent.
- Reminders back off after missed days and stop after a week.

**Widgets put the streak on the home screen.** A small widget shows the two cats on the condo with the streak numeral and today's paws. A medium widget adds the tables where it's your move, plus a paw button when you're waiting on your partner. Lock screen widgets show the numeral and today's paw state. StandBy shows the sleepy-night version. The widgets refresh when a push arrives, when the day rolls over and when the app updates them.

**The server owns the truth.** A new `Pair` Durable Object holds each streak, and a new `Player` Durable Object holds each person's reminder clock. `DeviceIndex` gains the phone's time zone and quiet hours. `GameRoom` reports every completed human turn to the pairs at its table.

**It ships in six PRs** after this doc (§15): server core, app streak UI with "Play again", notifications, widgets, reward art, and an optional Live Activity.

## 6. What counts as "playing today"

### 6.1 Definitions **(call)**

- **Shared table:** a Cat Tower room in `playing` status where both people of the pair hold a human seat. A seat on the same phone counts too, so pass-and-play on the couch counts. Bot seats are ignored.
- **Turn:** a completed turn by a human seat, ended by that seat's own action (a discard, or going out). Drawing alone is not a turn. A turn taken by a bot, or by a future bot takeover, never counts.
- **Pair:** two distinct person ids that have each completed at least one turn at the same shared table. A pair forms on its first such turn and lasts until either person leaves it (§14).
- **Day:** each person's local calendar day, rolling over at **04:00** local time. A turn at 1 a.m. counts as "tonight", not tomorrow. The day of a turn is computed in the time zone of the person who took it.
- **Kept day:** at least one turn by either person of the pair at any shared table on that day.
- **Together day:** both people took at least one turn at a shared table that day. The app shows it as two gold paws.
- **Held day:** there was a shared table in play all day, but neither of the two ever held the move, because a third human held it. This happens only at family tables with three or more humans. A held day neither grows nor breaks the streak, and the app shows it as a plain day **(call: fairness at family tables)**.
- **Missed day:** none of the above, and no pause.
- **Streak count:** the number of kept days in a row, including today once today is kept. Nap, held and paused days don't add to it, but they don't break the run either. The count shown during the day is the count through yesterday until today is kept, and then it goes up by one at once (the Duolingo "extend" moment).

### 6.2 Why "either of you", with "both" as the gold tier **(call, research)**

Three rules were weighed:

1. **Both must take a turn every day** (Duolingo friend streak style). Cat Tower turns depend on each other, so this is unfair. If your partner sits on the move all day and plays at 11 p.m., you couldn't play until then and you lose the day for something you didn't do. Fixing that takes grace windows and blocked-time accounting, and then every miss raises the question of whose fault it was. That is exactly what we must never show.
2. **Daily mini-game** both play on their own (like a daily puzzle). It avoids the dependency, but it is a second game to design and art up. Worse, the daily habit would then be the mini-game and not playing *with* each other. JD wants to play with his wife **(JD)**.
3. **Either takes a turn; both earns gold** (chosen). It is simple, and nobody can be blocked: whoever holds the move can keep the day. In a two-person game the turns alternate, so the streak still needs both of you. JD can't play two days in a row at one table unless his wife played in between. The gold together day, and the toy and perfect-week nap that come with it, pull toward both of you playing every day, with a reward instead of a penalty. Silverman & Barasch found that blame for a break makes it hurt more and drives people away (§4.5). This rule removes the unfair misses, the ones where you couldn't have played. The app never assigns a miss to anyone.

**The honest limit.** At a single two-person table, a missed day does mean the person holding the move didn't play, and both of you can work that out, because "your move" is visible all day. The design never *says* it. Settled days show only kept, gold, nap or held, with no record of whose move it was. The status pushes never name anyone. A nap or the win-back usually absorbs the miss first. Removing even that inference would need a rule that hides whose move it is, which would wreck the "your move" cue the game depends on. So this design accepts it. JD should confirm (§17 Q1).

One honest edge in the other direction: with several shared tables, one person can keep the day alone for a few days by working through the tables where it's their move. That's fine. Those turns become moves waiting for the partner, and this pull toward "your move" is the point.

### 6.3 Time zones and the day boundary **(call)**

- Each phone reports its IANA time zone (`TimeZone.current.identifier`) on launch, on foreground, and when `NSSystemTimeZoneDidChange` fires. `DeviceIndex` stores it. A person's time zone is the most recently reported one of their devices.
- Day key = the `YYYY-MM-DD` of `(instant − 4h)` in that zone. The Worker computes it with `Intl.DateTimeFormat`, which handles DST. On DST days the day is 23 or 25 hours long, and nothing special happens.
- **Settlement:** a pair's day `D` is settled once *both* people's day `D` has ended, plus 10 minutes. The `Pair` object's alarm is set to that instant. Before then, today's state is live.
- **Travel:** a day that had a turn is kept, whatever the clock did. A flight that skips most of a day may produce a miss, and the naps exist for that.
- A person with no reported time zone yet uses their partner's, then `America/Los_Angeles` **(call: JD's household; also the server's fallback for both)**.

## 7. One shared streak per pair (not personal, not per table) **(call)**

- **Not a personal streak.** A personal streak rewards playing alone, which here would mean bots, and the point is together. Two numbers would also split attention, and the clearest lesson from Duolingo is that the streak works because it's one number you care about (§4.1). The app keeps lifetime totals per pair, not per person.
- **Not per table.** Tables end, since a game finishes in days, and new tables get new codes. A streak tied to a table would die with every game. The pair is what lasts.
- **Many pairs per person.** A family table makes one pair for each two people who play there. The pair shown first everywhere is your **top pair**: the one with the longest current streak, with the most recent turn breaking ties. You can pin another one (widget configuration and the Us screen).
- **Same-phone pairs** (pass-and-play) are ordinary pairs. Their pushes go to the one phone, titled with whose turn it is, as today **(app)**.

## 8. Naps, win-back, pause and fresh start

### 8.1 Cat naps (streak freeze) **(call, research)**

- The pair shares one pool of naps, at most **2** (Duolingo found that letting people hold two raised daily actives without adding days off; §4.1). A shared pool means a nap is never "yours" or "mine". It's "ours", and using one blames nobody.
- **Earned:** 1 at the 7-day milestone, and 1 for each perfect week (seven together days in a row, not counting naps, holds or pauses; Duolingo's perfect week rewards a week kept without freezes [5]). Never bought.
- **Applied automatically** at settlement to a missed day. The day shows as a cat asleep under a blanket. The next morning both get a quiet push: "A cat nap covered yesterday. 12 days and counting." It's informative, and it doesn't say whose day it was.
- The count doesn't go up on a nap day, but the run continues.

### 8.2 Win-back (repair) **(call, research)**

- If a day is missed with no naps left, the streak doesn't drop to 0 right away. It goes into **win-back**. The numeral wears a bandage, and two empty paw dots show beside it, so progress starts endowed (§4.4).
- **Keep the next two days** (any kept days, not necessarily together days) and the streak comes back whole. The missed day becomes a nap day, and the count carries on.
- If either of those two days is missed, the streak ends. It resets to 0, and any of those days that was kept starts the new streak.
- It's free and earned by coming back, which mirrors Milkman et al.'s finding that rewarding the return after a miss works best (§4.5). Duolingo charges for repair, and deceptive.design lists that as a dark pattern (§4.5). We don't.

### 8.3 Pause **(call)**

- Either person can pause the pair's streak for **1 to 14 days** from the Us screen (a suitcase icon and a day dial). Paused days neither grow nor break it. Pausing again extends the pause, and either person can end it early.
- Both see the suitcase on the badge and widget. The partner gets a quiet push: "JD put the cats to bed for 3 days."
- **No reminders** for that pair during a pause. "Your turn" pushes still come, because a turn is still a turn.
- **Limit:** none in v1 **(call: it's two adults who love each other; see open questions)**.

### 8.4 When a streak ends: the fresh start **(call, research)**

- The current count goes to 0. **Best streak**, **days together** (lifetime kept days) and **together days** (lifetime gold days) stay big on the Us screen, so the history never goes away.
- The Cat Condo never shrinks (§9.1).
- **No "streak lost" screen.** The next time you open the app, the condo cats are curled up asleep, and the numeral is a fresh 0 with a soft sparkle that invites a new one.
- On the next Monday or the 1st of the month, whichever comes first, and only if the pair hasn't already started again, each person gets one push at their usual time: "New week, new deal. One turn starts a streak with Mia." (Fresh start effect: temporal landmarks make a new attempt more likely, §4.5.) It's sent once per break.

## 9. Milestones and rewards

Every reward is cosmetic or a celebration. Every reward is earned only by playing together, never sold, and never needed to play **(call, research: Deci et al. on rewards crowding out intrinsic motivation; Apple 5.1.2)**.

### 9.1 The Cat Condo (the thing that grows) **(call)**

The pair's shared cat tree. Your two cats sit on it. It's the hero of the Us screen and the small widget. It grows a stage at **lifetime days-together** thresholds, and those **never go down**. So a broken streak never takes away what the two of you built. Only the streak numeral resets.

| Stage | Lifetime days together | What's added |
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

**Why a condo, not a cat that grows:** the cats are each person's avatar, and they're whole-cat sprites, 8 cats in 7 poses **(app)**. Ageing or levelling them would mean regenerating 56 sprites per level and keeping them consistent. A condo is one illustration per stage. Each stage is generated with the previous stage as an extra `-i` reference, the same way the cat pose sets were kept consistent.

### 9.2 Streak milestones and gift boxes **(call, research)**

- **Milestones:** 3, 7, 14, 30, 50, 75, 100, 150, 200, 250, 300, 365, then every 100. They come quickly at first and then the gaps widen (goal gradient; quick early wins, §4.4). The Us screen always shows the distance to the next one as a progress arc that starts part-filled.
- **Each milestone hands both people a gift box**: a glossy box tied with magenta yarn. The pair gets the same content, decided by the server when the milestone is reached. Either person can open it; for the other, it stays wrapped until they open it themselves. Both get to unwrap.
- **What's inside (variable):** the server picks something the pair doesn't own yet, from a tier set by the milestone:
  - small milestones (3, 14, 50, …): a toy or a card back;
  - big milestones (7, 30, 100, 365): a rug or a rare card back, plus a nap at 7.
  - Once everything is owned, gifts give toys and a confetti burst.
- **Repeats after a reset:** milestones give gifts again every time they're reached, so a fresh start gets its quick wins at 3 and 7 days again.
- **When it's opened:** on Home or the Us screen, never mid-table **(call: don't break the game's flow; the turn cue owns the table)**.

### 9.3 Toys (the daily surprise) **(call, research)**

- On every **together day**, one toy drops onto the condo: a yarn ball, feather wand, cardboard box, mouse, fish, bell, laser dot, catnip sack and so on. There are 24 to collect, in three rarities (16 common, 6 shiny, 2 golden).
- **No duplicates** until the set is done. A shiny is guaranteed at least once every 7 together days, and a golden at least once every 30, so luck can't stretch the set out forever.
- The drop happens when the second turn of the day lands. The person who completed the day sees it live, and the other sees it at their next open. That moment is the variable reward: small, frequent and surprising, but never spendable or tradable (§4.5 on variable rewards versus gambling).
- **A full set** unlocks the golden yarn card back.

### 9.4 Card backs and rugs (things the table shows) **(call)**

- **Card backs:** the default violet paw, plus 6 to unlock: yarn swirl, moonlit fish, cucumber chaos, crown, heart paws and golden yarn. Text-free art, thick ink outline, saturated palette, never the four-color set **(JD)**.
- **Rugs:** the default magenta/teal/orange rug, plus 4 to unlock: night sky, candy stripe, fish pond and royal violet.
- **Equipping:** whoever creates a table picks its rug and card back in the lobby, from anything they've unlocked with anyone. Their last choice is remembered. Everyone at the table sees it. The server stores `look: {rug, back}` on the room, checked against the known ids. It isn't checked against ownership, since this is cosmetic and the lobby only offers what you own. Tables created before this get the defaults.

### 9.5 Celebrations **(call)**

- **Day kept** (your turn kept today): the streak badge in the table's top bar does a paw *stamp*. The numeral rolls up by one, and there's a sparkle with `sfx-sparkle` and a light haptic. It lasts under a second and never blocks the next action.
- **Together day:** a double stamp, gold, and a toy arcs from the badge to the corner. It's a stronger haptic.
- **Milestone:** the gift box waits on Home. Opening it is full screen: the box wiggles, bursts into confetti, and the reward spins in on a sunburst, reusing `Celebrations.swift` effects. Both cats do their `celebrate` pose.
- **Condo stage:** the new piece drops in with squash and stretch, and the cats leap onto it.
- **Reduce Motion:** fades instead of arcs, and no shake (parent spec §13).

### 9.6 Art list (Codex pipeline, placeholders first) **(call)**

New prompt files under `Art/prompts/habit/`, all in the house style block from `push-priming.txt`:
- `condo-1` … `condo-10`: whole illustrations, square, with transparent cutout;
- `toy-*` (24);
- `back-*` (6) and `rug-*` (4);
- `gift-box` (closed, open);
- `paw-badge` states: grey, half (one paw), gold (both), nap blanket, bandage, suitcase;
- `cats-asleep-condo` for StandBy and night.

JD approves them in three batches: (1) badge states, the gift box and condo stages 1-5; (2) toys; (3) backs, rugs and condo stages 6-10.

## 10. In-app surfaces

### 10.1 Home **(call)**

- Top center, beside the hero: the **streak badge** (two paws plus the numeral). It's live for the top pair. If you have no pair yet, it shows the grey paws and a 0, which pulse gently once you're seated at a shared table.
- A tap opens the **Us screen**.
- The table tiles keep their "your turn" bell. A table that would **keep today** gets a small gold paw on its corner.

### 10.2 The Us screen (new) **(call)**

- The full **Cat Condo** with both cats, the toys scattered on it, and the big numeral.
- Under it, three stat tiles (Duolingo's three-tile pattern; mobbin note): **best**, **days together** and **together days**, each a numeral with an icon.
- **This week's strip:** seven paw dots, showing grey, kept, gold, nap, held or suitcase per day. It never shows who played.
- The **next milestone** arc.
- Unopened gift boxes.
- Two round buttons: **suitcase** (pause) and **bell** (reminder settings, §12.6).
- If there are several pairs, a row of partner cats at the top switches between them.
- When there's no shared table in play, a big **Play** pill starts a table with that partner. It reuses create plus share, or "Play again" when there's a finished table (§10.4).

### 10.3 Table top bar **(call)**

A small streak badge for the top pair sits at the table, but only when both people of that pair are seated here. That's where the stamp celebrates.

### 10.4 "Play again" (enabler) **(call)**

- A streak stalls whenever a game ends and nobody starts a new one. So `GameOverView` gets a **Play again** pill.
- **Server:** a new message, `{ t: "rematch" }`, available to any seated human once the room is `over`, and accepted once per room. It creates a new room with the same name and look, fills its seats straight from the old room's seats (the same `person` and `deviceId` for humans, the same bots), and **deals at once**, with no lobby. The first seat rotates to the seat after the old game's first seat.
- It posts `rematch: <newCode>` to everyone in the old room. Every other human gets the "Play again" push ("Mia dealt a new game."). Whoever holds the first move also gets the normal "your move" push. **(call: a lobby would let a partner who never opens the app stall the new table, which defeats the point.)**
- The old room's `/tables` entry points to the new one, so Home shows the new table in its place. This closes the parent iOS spec's server follow-up #2.

## 11. Widgets

A widget extension target, `PounceWidgets` (`com.conleychaos.play.widgets`). It shares an **App Group** (`group.com.conleychaos.play`) for the cached streak snapshot and the art, and a **keychain access group** so its one intent can call the server with the device token **(call)**.

| Widget | Family | Shows | Tap / action |
|---|---|---|---|
| **Us** | `systemSmall` | The condo with both cats (pose per state, below), the numeral, and today's paws (grey, half or gold). | Opens the table where it's your move, otherwise the Us screen. |
| **Us + tables** | `systemMedium` | Left: same as small. Right: up to 2 shared tables, each with the table name and either your bell ("your move") or the partner's cat ("their move"). On a "their move" row there's a round **paw** button. | Row: opens that table. Paw button: sends a paw (interactive `AppIntent`; §12.4), then shows "sent" (a check on the paw) until tomorrow. |
| **Streak** | `accessoryCircular` | The paw ring with the numeral; the ring fills halfway or fully for today. | Opens the Us screen. |
| **Us** | `accessoryRectangular` | Partner's cat (template-rendered), numeral, and a bell when it's your move. | Opens your move. |
| **Inline** | `accessoryInline` | The paw image plus "12 · Mia" (numeral and name; the only words are a name, per the no-text rule). | Opens the app. |
| **StandBy** | `systemSmall` in StandBy | The night art: both cats asleep on the condo, with the numeral. It's red in night mode. | — |

**Cat poses per state:**
- your move and today not kept: your cat awake, partner's cat looking at you;
- their move: your cat idle, partner's cat awake;
- kept: one cat in `celebrate`;
- together: both in `celebrate`;
- paused: both asleep;
- win-back: the bandage on the numeral.

All poses reuse the existing cat sprites **(app)**.

**Configuration:** a `WidgetConfigurationIntent` with one parameter, *partner*. It defaults to the top pair and is listed by the partner's name and cat.

**Freshness** (WidgetKit budget about 40 to 70 reloads a day [36]):
- **Timeline:** entries for the next state changes the widget can predict: the 4 a.m. rollover (today goes back to grey), the end of a pause, and the evening, when the "at risk" pose begins. No network is needed for these.
- **App:** writes the snapshot to the App Group and calls `WidgetCenter.reloadTimelines` whenever it fetches streaks, and once more when it goes to the background [38]. Foreground reloads don't use the budget [36].
- **Notification Service Extension:** every alert push carries the `streak` block (§12.7). The extension writes it to the App Group and reloads timelines. *Verify on device in PR 4 that a reload from the service extension takes effect. If it doesn't, the widget push below covers it.*
- **WidgetKit push** [37]: the widget extension adopts `WidgetPushHandler`, and its `pushTokenDidChange` uploads the token (`PUT /v1/devices/me/widget-push`, using the shared keychain credential).
  - The server sends `apns-push-type: widgets`, topic `com.conleychaos.play.push-type.widgets`, body `{"aps":{"content-changed":true}}`, `apns-priority: 5`.
  - It sends one when the pair's widget state changes *without* an alert to this device: the partner kept or gilded today while it wasn't your move, settlement at rollover, a pause, or a paw resting.
  - **Server throttle:** at most one per device every 15 minutes (Apple asks providers to throttle [34]).
  - The push carries no data, so on reload the provider does one short `GET /v1/devices/me/streaks` (5-second timeout) and falls back to the App Group snapshot.
- **Server truth** always wins on the next app open.

**Rendering:** glass, tinted and clear home screens (`widgetRenderingMode`). In accented and vibrant modes, the cats and condo use mono template versions and the numeral is `widgetAccentable` **(call)**.

**Live Activity:** not for the daily loop. A Cat Tower game lasts days, longer than a Live Activity can (§4.4), and a permanent lock screen banner for "your move" would be the nagging we promised not to do. An **optional** "live table" activity comes in the last phase (§15). It starts only when you leave the app mid-round while your partner is awake at the same table. It shows whose move it is and both cats, updates by push on each turn, and ends at the end of the round or after 30 minutes with no move. While it runs, the "your move" alert for that table is suppressed, because the HIG says not to duplicate a Live Activity with notifications [42].

## 12. Notifications

### 12.1 The set **(call)**

| Kind | When | Who gets it | Interruption | Cap |
|---|---|---|---|---|
| **Your move** (exists, new copy) | Your partner's turn hands you the move and you're not awake in that room. | The person whose move it is. | `active`; `passive` during quiet hours | Once per turn (exists), collapsed per table (exists) |
| **Daily reminder** | At your usual time (§12.3), if today isn't kept for your top pair, it's your move at a shared table, and you haven't opened the app in the last 2 hours. | You. | `active` | 1 a day |
| **Last chance** | 90 minutes before your quiet hours start, if today still isn't kept, the streak is 3 or more, and it's your move. **On by default**, and one toggle turns it off. Duolingo's first big streak win was its late-night streak saver [10] **(call; see open questions)**. | You. | `active` (not Time Sensitive; §12.5) | 1 a day, counts toward the 2 |
| **Paw from partner** | Your partner taps the paw (widget, Us screen, or "their move" on Home). | You. | `active`; held until your quiet hours end | 1 a day per pair, from each side |
| **Nap used** / **win-back** / **paused** | At settlement, or when a partner pauses. | Both. | `passive` (no sound, no light-up) | — |
| **Milestone** | A milestone was reached and you weren't in the app. | Both. | `active` | — |
| **Play again** | A partner started a rematch. | The others. | `active` | — |
| **Fresh start** | The first Monday or 1st of the month after a streak ended (§8.4). | Each person, at their usual time. | `active` | Once per break |

**Hard caps** (the `Player` DO enforces them):
- at most **2 reminder-type pushes a day**, where reminder-type means the daily reminder, last chance, paws and fresh start. "Your move" pushes are driven by events, deduped per turn, and not counted, because they're the game;
- at most **one push of any kind every 20 minutes**, except "your move" (§4.3 backoff guidance);
- never in quiet hours, except "your move" as `passive`.

### 12.2 Copy **(call)**

The voice is the cats, warm and a little dramatic about *themselves*, never about the partner. Copy names people, not blame. There's no emoji, no countdown and no guilt. Titles stay the name of the person the push is for, which matters on shared phones **(app)**.

| Kind | Title | Body (rotated, no repeat within 7 days) |
|---|---|---|
| Your move | JD | "Mia played. Your move at Couch Cats." / "Mia played. Play back and it's a together day." (the second when your turn would make today gold) |
| Daily reminder | JD | "The cats are on the rug. Your move at Couch Cats." / "Day 13 is up for grabs. One turn keeps it." / "Mia's cat is guarding the deck. Your move." / "A turn with Mia, then the couch." |
| Last chance | JD | "One turn tonight keeps 12 days going." / "The cats want one more turn before bed." |
| Paw | JD | "Mia sent a paw. Your move at Couch Cats." |
| Nap used | Couch Cats | "A cat nap covered yesterday. 12 days and counting." |
| Win-back | Couch Cats | "Two days in a row brings 12 back." |
| Paused | Couch Cats | "Mia put the cats to bed for 3 days." |
| Milestone | Couch Cats | "30 days together. There's a gift on the rug." |
| Play again | Couch Cats | "Mia dealt a new game." |
| Fresh start | JD | "New week, new deal. One turn starts a streak with Mia." |
| Last reminder before going quiet (§12.3) | JD | "The cats will keep your seat warm." |

**Never written:**
- "Mia is waiting on you";
- "Don't break your streak";
- "You missed yesterday";
- anything with a timer;
- anything addressed to the partner about the other's absence.

### 12.3 Timing, backoff and quiet hours **(call, research)**

**Usual time:**
- For each person, the `Player` DO keeps a histogram of the local time of their **first turn of each day**, in 30-minute buckets, separately for weekdays and weekends. Each day's weight is multiplied by 0.85, so recent habits count most.
- The reminder fires 15 minutes before the weighted median.
- Until 5 days of data exist, it uses 7:30 p.m. local.
- It's always clamped to outside quiet hours and at least 2 hours before quiet hours start.
- This is the simple form of Duolingo's lesson, "send near when the person usually practices" (§4.1). A bandit needs far more users than a family TestFlight, so copy rotation is plain round-robin.

**Backoff** (for the person, counted in days they took no turn at any shared table):
- after 2 such days: no last chance;
- after 4: the daily reminder only every other day;
- after 7: one "The cats will keep your seat warm." and then no reminders at all.
- The person's next turn resets everything.
- Partner paws still work during backoff, but after **3 unanswered paws in a row** the paw button rests for 3 days (it shows a sleeping paw). That stops one partner nagging the other through us (§4.5 on nagging).

**Quiet hours:**
- The default is 22:00 to 08:00 local, per phone, set in Settings with two dials (a moon and a sun, no words).
- Reminders and paws never go out in quiet hours. Paws wait until quiet hours end.
- "Your move" pushes during quiet hours go as `passive`. They land silently in Notification Center, so the move is there in the morning without a buzz at 2 a.m.

### 12.4 Partner paw (nudge) **(call)**

- Offered only when **it's the partner's move** at a shared table and today isn't kept: a "their move" row on the medium widget, the Us screen, or a long-press on that table's tile on Home.
- `POST /v1/pairs/{pairId}/paw`. The server checks the rate limit (1 per sender per pair per day, and the 3-unanswered rest), holds it through the recipient's quiet hours, and counts it in the recipient's 2-a-day cap. If the cap is full, the paw is delivered as `passive` instead of being dropped, so the sender's gesture still arrives.
- The sender sees a check on the paw. The recipient's next turn clears the "unanswered" count.

### 12.5 iOS specifics **(call, research)**

- **Authorization:**
  - The existing priming screen and system prompt stay as they are, asking for alert, sound and badge **(app)**.
  - **New:** if someone taps "Not now" on priming, the app requests **provisional** authorization, which shows no prompt. Reminders then arrive quietly in Notification Center with iOS's own Keep / Turn Off buttons. It's a trial the person controls, and it means "not now" isn't "never" (§4.3).
  - The bell on Home still offers the full prompt once.
- **Interruption levels:** "your move", daily reminder, paws, last chance, milestones and play again are `active`. Status changes (nap used, win-back, paused) are `passive`. **No Time Sensitive in v1.** Apple reserves it for things that need attention right now, and Focus can let it break through. A card game isn't that, and a streak isn't an emergency. Using it would spend trust we need (§4.3).
- **Grouping:**
  - `thread-id` = room code for table pushes (exists), `pair:<pairId>` for streak pushes. No `summary-arg`: iOS has ignored it since iOS 15 [26];
  - collapse id = room code for "your move" (exists) and `pair:<pairId>:<kind>` for the others, at most 64 bytes [27];
  - `relevance-score`: "your move" 1.0, reminders 0.6, status 0.2, for the scheduled summary.
- **Badge:** the server sets `aps.badge` = the number of tables where it's your move. The app sets the same number when it refreshes tables.
- **Categories and actions:**
  - `YOUR_MOVE` and `REMINDER`: **Play** (`.foreground`, opens the table; the lock screen "take your turn", which needs the app because a turn needs the table) and **In an hour** (background: schedules a local reminder 60 minutes later, reusing the local reminder path; no server call).
  - `PAW`: **Play** and **Paw back** (background: a `POST` to the paw endpoint, sending one back. It's capped like any paw, so "Paw back" to a paw that answered yours is free and fun). Apple publishes no time budget for background actions [28], so the request runs inside `beginBackgroundTask`, carries an idempotency id, and is retried on the next launch if it didn't finish.
  - `STATUS`: none.
- **Notification Service Extension** (`PounceNotify`, `com.conleychaos.play.notify`), triggered by `mutable-content: 1` on every push:
  - It makes partner pushes **communication notifications**: an `INSendMessageIntent` whose sender's avatar is the partner's cat face from the shared art. "Mia played" then shows Mia's cat where the app icon would be. That needs the Communication Notifications capability (§4.3).
  - It writes the `streak` block from the payload into the App Group and reloads the widgets (§12.7).
- **Foreground behaviour** (exists): a banner for the table on screen is dropped. New: streak pushes are dropped while the Us screen is on screen.

### 12.6 Reminder settings (in-app) **(call)**

On the existing settings sheet (gear) and the Us screen bell:
- one bell toggle (reminders on or off for this phone; "your move" is unaffected);
- the moon and sun quiet-hours dials;
- one toggle with a crescent-moon-and-bell icon for the last chance.

Everything is pictures plus numerals (times shown in the phone's locale format). The settings go to the server with the profile (§13.4).

### 12.7 Payload additions **(call)**

Every push to a person who is in a pair gets a small top-level `streak` object for the extension:

```json
{
  "aps": {
    "alert": {"title": "JD", "body": "Mia played. Your move at Couch Cats."},
    "sound": "default",
    "thread-id": "GH2VD",
    "mutable-content": 1,
    "category": "YOUR_MOVE",
    "interruption-level": "active",
    "relevance-score": 1.0,
    "badge": 2
  },
  "code": "GH2VD",
  "kind": "your_move",
  "from": {"name": "Mia", "cat": 2},
  "streak": {"pair": "p_3f9c…", "count": 12, "today": "half", "myMove": ["GH2VD"], "theirMove": [], "naps": 1}
}
```

That's about 400 bytes, well under APNs' 4 KB.

## 13. Server design

### 13.1 Identity: who a "person" is **(call)**

- Streaks key on **person ids**, not device ids. A device id changes on a re-mint after a 401 **(app)**, and one phone can hold several people.
- **Cross-device:** today the iPad and the iPhone each create their own owner person at Pick your cat, so JD on the iPad would be a different person. Fix: the app keeps the **owner** `Person` (and a per-person secret, below) in a **synchronizable Keychain item**. A new device of the same Apple ID that finds one adopts it instead of asking Pick your cat again. There's no new entitlement, because it uses iCloud Keychain when the person has it on. Existing devices with their own owner keep it. Merging two owners is not in v1 (see open questions).
- **Binding a person to a device:**
  - Person ids are visible to everyone at a table **(server)**, so knowing one must not be enough to get someone's reminders.
  - On first registration the app sends a random 32-byte `personKey` (kept in the Keychain beside the person). `Player` stores its SHA-256, trust on first use.
  - Attaching a device to that person later needs the same key.
  - Turn attribution still trusts seat claims, as the game does today. The worst a cheat could do is keep someone's streak alive, which is acceptable at this scale. Sign in with Apple (M2) replaces this.

### 13.2 Durable Objects **(call)**

**`DeviceIndex` (exists, per device), gains:**
- a `profile` row: `time_zone`, `quiet_start` and `quiet_end` (minutes after midnight), `reminders` (0/1), `last_chance` (0/1), and `updated_at`;
- `people`: the person ids on this phone, each with its name and cat;
- `widget_push_token`, and `live_activity_tokens` later;
- the push path: `push(intent)` now picks `active` or `passive` from the quiet hours, adds the `streak` block, sets `badge`, `category` and `mutable-content`, and forgets dead tokens as today.

**`Player` (new, one per person id, named by person id):**
- `meta`: name, cat, `key_hash`;
- `devices(device_id, attached_at)`;
- `pairs(pair_id, partner_id)`;
- `playtime(bucket, daytype, weight)`, the 48 × 2 histogram;
- `reminders`: today's day key, `sent_today`, `last_sent_at`, `backoff_days`, `last_turn_day`, `rotation` (copy index per kind), and `fresh_start_sent_for` (a break id);
- an **alarm** at the next reminder decision time. At the alarm it asks each pair `today()`, decides by §12.1 and §12.3, and pushes through each of its devices' `DeviceIndex.push`.

**`Pair` (new, one per unordered pair, named by `pairId` = the base64url SHA-256 of `"pair:v1:" + min(a,b) + ":" + max(a,b)`, truncated to 22 characters):**
- `people(person_id, name, cat)`, two rows;
- `streak` (one row): `count`, `run_started_day`, `last_settled_day`, `best`, `lifetime_kept`, `lifetime_together`, `perfect_run` (together days in a row toward a perfect week), `naps`, `winback_from_day` (null, or the missed day), `winback_kept` (0-2), `paused_until_day`, `paused_by`, `break_id`;
- `days(day TEXT PRIMARY KEY, turns_a, turns_b, had_move INTEGER, state TEXT)`, where `state` is one of `live`, `kept`, `together`, `nap`, `held`, `paused`, `missed` or `winback`. Kept for **120 days**, plus the lifetime counters **(call)**;
- `moves(code PRIMARY KEY, holder_id, since)`: who holds the move at each shared table, and `active` tables;
- `rewards`: `owned(item_id, got_at)`, `gifts(gift_id, milestone, item_id, opened_a, opened_b, created_at)`, `toys_pity(shiny_since, golden_since)`;
- `paws(sender_id, day, unanswered)`;
- an **alarm** at the next settlement instant (§6.3).

### 13.3 Flows **(call)**

1. **Turn completes** in `GameRoom` (`core.ts`, where `turn` is emitted for the next seat):
   - If the seat that just finished is human, a new `StreakIntent {by, at, code, next}` is drained beside the push intents.
   - For each other human person `p` at the table, `GameRoom.after()` calls `Pair(by, p).turn({by, at, code, nextHolder})` with `waitUntil`. It's retried once, and a failure is logged, never fatal: a lost streak update is cosmetic, and the game is saved.
   - The `Pair` records the day key (taker's time zone, fetched from `Player`, then `DeviceIndex`), updates `moves`, and settles any days past due first.
   - If this is the first turn of today, `count` goes up at once, and the response tells the room so the app can stamp. If it's both people's first turn, it's a together day: a toy is drawn.
   - It returns a small `StreakView` that the room broadcasts to the two people's sockets as a new server message, `{ t: "streak", pair, view }`, so the table badge stamps live.
   - The `Player` of the person who played records the playtime bucket.
2. **Move arrives** (`nextHolder` is in the pair): `moves` is updated and `days[today].had_move = 1`. The "your move" push goes out as today **(server)**, with the new copy, using `from` = the person who just played.
3. **Settlement alarm** (in `Pair`): for each unsettled day up to the latest one both people have finished, it applies §6.1, §8.1 and §8.2 in order:
   1. paused;
   2. kept or together;
   3. held (`had_move = 0`, and a shared table was `active` the whole day);
   4. otherwise a nap if one is left;
   5. otherwise win-back or a reset.

   It updates milestones, gifts, perfect weeks and naps, asks both `Player`s to send any status push, and re-arms for the next day.
4. **Room ends or closes**: the room tells its pairs to drop its row from `moves`.
5. **Reminder alarm** (in `Player`): computes the decision at the reminder time and the last-chance time, and re-arms for tomorrow.

### 13.4 HTTP API (device token auth, as today) **(call)**

| Method and path | Body / result | Notes |
|---|---|---|
| `PUT /v1/devices/me/profile` | `{timeZone, quietStart, quietEnd, reminders, lastChance, people: [{id, name, cat, key}]}` → 204 | Sent on launch, on foreground when anything changed, and on a time zone change. Attaches each person to this device (§13.1). It's within the existing 1 KB body cap for up to 4 people, so that cap rises to 2 KB for this route only. |
| `GET /v1/devices/me/streaks` | `{pairs: [StreakView]}` for every person on this phone | `StreakView` = `{pair, me, partner: {name, cat}, count, today: "none"\|"half"\|"together", mine, theirs, naps, winback: {kept, of: 2}\|null, pausedUntil, best, lifetimeKept, lifetimeTogether, week: [7 states], next: {milestone, at}, condoStage, toys: [ids], unlocked: [ids], gifts: [{id, milestone, item, opened}], myMove: [codes], theirMove: [codes], pawSent, pawResting}` |
| `POST /v1/pairs/{pair}/paw` | `{from}` → 204 / 429 | `from` must be a person on this device. |
| `PUT /v1/pairs/{pair}/pause` | `{from, days: 1-14}` → 204 | |
| `DELETE /v1/pairs/{pair}/pause` | `{from}` → 204 | |
| `POST /v1/pairs/{pair}/gifts/{id}/open` | `{from}` → 204 | Marks it opened for that person. |
| `DELETE /v1/pairs/{pair}` | `{from}` → 204 | Leave the streak (§14). |
| `PUT /v1/devices/me/widget-push` | `{token}` → 204 | Called from the widget extension's `WidgetPushHandler` (§11). It's a separate token from the app's APNs token, sent with the widgets push type and topic. |

**WebSocket additions:** the server message `{t: "streak", pair, view}`, and the client message `{t: "rematch"}` (§10.4). `PROTOCOL_VERSION` stays 1: both are additive, and older apps ignore unknown messages **(call, check against the client's decoder before merging)**.

### 13.5 Limits and costs **(call)**

- A pair object wakes about once a day for settlement and once per turn.
- A player object wakes up to 3 times a day.
- At family scale that's a rounding error on Durable Objects pricing.
- The `days` table at 120 rows per pair is tiny.

## 14. Privacy

- **What's new on the server:**
  - each phone's time zone and quiet hours;
  - per person, a histogram of what times of day they start playing;
  - per pair, the daily turn counts for 120 days, the lifetime counters, and the rewards.
- **Never collected:** location (the time zone is enough), contacts, ad identifiers, or analytics.
- **Who sees what:**
  - your partner sees the pair's shared state: the count, today's paws (half or gold), the week's strip, rewards and gifts;
  - your partner never sees your play-time histogram, your reminder settings, or a per-person history of who played on which past day;
  - "half" today, meaning one of you has played, is visible to both, because it's what tells you it's your move. Once the day settles, only kept, together or nap remains.
- **Lock screen:** pushes show names and table names, as today **(app)**. iOS's own "Show Previews" setting hides them.
- **Leaving:** either person can **leave a streak** (Us screen → hold the partner's cat → a trash can). That deletes the `Pair` object and its history for both, and both people's `Player` forget it. The partner sees that pair disappear, with no push.
  - **Leaving sticks.** The leaver's `Player` keeps a tombstone for that partner's person id, so the pair doesn't re-form the next time they play together.
  - Only the leaver can undo it: in the Us screen's partner row, a ghosted cat with a plus starts a fresh pair at 0. The deleted history doesn't come back **(call)**. Deleting the app's last person on a phone (People sheet) leaves every pair of that person. A `Player` with no devices left for 90 days deletes itself **(call)**.
- **Retention:** day rows after 120 days, `Player` objects after 90 idle days, and pairs whose people both have no devices after 90 days.
- **Logging:** no person ids, pair ids, names or tokens in logs. This follows the existing rule: invocation logs are off because URLs carry room codes **(server)**, and pair URLs carry pair ids, so the same rule applies.
- **App Store privacy:** `PrivacyInfo.xcprivacy` adds **Product Interaction** (play times) and **Other Usage Data** (streak state), both for App Functionality only, not linked to identity beyond the existing device ID, and no tracking. The privacy label in App Store Connect needs the same update before external TestFlight review.

## 15. Phasing into shippable PRs

Each PR ships to TestFlight on its own and leaves the app working **(call)**.

| # | PR | Contents | Depends on |
|---|---|---|---|
| 0 | **This design** | The doc only. | — |
| 1 | **Server: streak core** | `Player` and `Pair` DOs plus the migration; `DeviceIndex` profile; turn reporting from `GameRoom`; day keys and settlement; naps, win-back, pause and held days; milestones, gifts and toys drawn on the server; the HTTP routes in §13.4 (except widget-push); `{t:"streak"}`. Unit tests with a fake clock across time zones, DST and the 4 a.m. rollover. No push changes yet. Turn reporting sits behind a `STREAKS` env var that stays off in production until PR 2 ships, so the first real streaks start with correct time zones **(call)**. | 0 |
| 2 | **App: streak UI and Play again** | Profile upload; the synchronizable owner Person and `personKey`; `StreakStore` in PounceKit; Home badge; Us screen; table top-bar stamp; gift opening; pause; leave streak. Server and app `rematch` with "Play again". All with **placeholder art** in the final names and sizes. | 1 |
| 3 | **Notifications** | Server: `Player` reminder alarms, learned time, caps, backoff, quiet hours (passive), paws, status and milestone pushes, the new "your move" copy, badge, category, `mutable-content`, and the `streak` block. App: categories and actions, provisional on "Not now", the settings dials, and the paw button in the app. The `PounceNotify` extension with communication-notification avatars. | 1, 2 |
| 4 | **Widgets** | The `PounceWidgets` target, App Group and keychain group; small, medium, the three accessory families and StandBy; the configuration intent; the interactive paw intent; timeline entries at rollover; reloads from the app and the extension; WidgetKit push updates if available. | 2 (3 for push refresh) |
| 5 | **Reward art and cosmetics** | Codex art in three approval batches (§9.6); rug and card-back picker in the lobby; `look` on rooms; toy drops on the condo; condo stages. Art swaps in for placeholders by file name. | 2 |
| 6 | **Live table (optional)** | The Live Activity in §11, updated by APNs `liveactivity` pushes from `GameRoom`. Built only if JD wants it after living with 1-5. | 3 |

The order is deliberate. The streak becomes visible (2) before it can nag (3). Notifications come before widgets because they're the bigger lever and the plumbing is already there. Art goes last because placeholders carry everything, per JD's rule.

## 16. Testing **(call)**

- **Server (vitest, as today):**
  - settlement table tests over sequences of turns in one and in two time zones;
  - DST forward and back;
  - a turn at 03:59 and at 04:01;
  - held days at a three-person table;
  - nap use and earning, perfect week, win-back success and failure, and pause;
  - milestones and gift content (seeded);
  - toy pity counters;
  - reminder decisions under caps, backoff, quiet hours and paws;
  - person-key binding.
- **App (PounceKit tests):** `StreakStore` decoding; badge state mapping; the widget snapshot; the `PushPolicy` additions.
- **UI tests:** the Us screen from `DemoFixtures` (a 12-day pair with a gift and a nap); the stamp after a turn on the dev server (`devSpeed`); "Play again".
- **Widgets:** Xcode previews for every family and state, checked in all rendering modes.
- **Push:** on TestFlight builds only, since dev builds get sandbox tokens **(app)**. A manual checklist is added to `MANUAL-CHECKLIST.md`.

## 17. Open questions only JD can answer

1. **"Either of you" or "both of you"?** The recommendation keeps the day when either of you takes a turn and makes it gold when both do (§6.2). Do you want the stricter rule, both every day, even though it can cost you a day your wife held the move? And at your usual single two-person table, the app never names who missed, but either of you can tell whose move it was. Is that acceptable, given that hiding it would mean hiding "your move"?
2. **More than one device?** Do you or your wife play on the iPad as well as the iPhone? If yes, the synced owner Person (§13.1) matters in PR 2. Your existing separate iPad person would need a merge, or you'd simply re-pick your cat on the iPad.
3. **Family pairs too, or only the two of you?** By default every two people who play together get a streak (mom, the kids). Or should only one "partner" pair have a streak?
4. **Your usual time and bedtime.** Are 10 p.m. to 8 a.m. quiet hours and a 7:30 p.m. first-week reminder right for your house? Is the evening last-chance push (on by default for streaks of 3 or more) welcome, or does it feel like pressure?
5. **Pause limits.** Is an unlimited pause (up to 14 days at a time) fine, or do you want it capped so the streak means something?
6. **Rewards at the table.** Is it right that the table's creator picks the rug and card back everyone sees (§9.4)?
7. **Live table.** Is PR 6 worth building at all?

## 18. Left to the builder

- Exact animation timings, haptic patterns and sound choices for the stamp, gift and condo (start from `Juice.swift` and `Celebrations.swift`).
- The exact toy, card-back and rug lineup, and the prompt wording, within §9 (JD approves the art).
- The internal shape of `StreakView` beyond the fields listed; SQL schemas and indexes; the migration tag names.
- How the medium widget lays out on iPad and in StandBy.
- The copy rotation order, and further lines in the same voice (JD reviews them in the PR).
- Whether `Pair.turn` is called directly or batched per room `after()`.

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
