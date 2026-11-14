# Pounce onboarding research: first run and invited players

Research brief, November 2026. Scope: how best-in-class mobile games handle (1) a brand-new player's first run and (2) a player who arrives through a friend's invite, with patterns ranked for Pounce (family, turn-based, live or async, kids and grown-ups, 5-character table codes, house-cat bots, optional Sign in with Apple).

## How to read this

Each claim carries a confidence tag:

- **[Primary]**: the company's own docs, help center, Apple documentation, or an interview with the team.
- **[Secondary]**: press, teardown, or guide site describing the product.
- **[Unverified]**: I looked and could not confirm it from a source. Treat it as a hypothesis to check by playing the game.

A recurring gap: nobody publishes screen-by-screen first-run flows for Royal Match, Candy Crush, or Monopoly GO, including when they ask for notifications. The only reliable way to get those is to install each one fresh and record it. I've flagged every place where that applies.

---

## 1. Casual FTUE leaders: Royal Match, Candy Crush, Monopoly GO, Wordle / NYT Games

### What they do

**Royal Match (Dream Games)**
- Time to fun is called "best-in-class" with "no visible loading screens", and the core loop is simple enough to onboard "even the most inexperienced of casual gamers." [Secondary] ([Naavik deep dive](https://naavik.co/deep-dives/royal-match/))
- The tutorial is light: short tooltips and little text. One teardown praises tooltips where "the quantity of the text was concise and impactful." [Secondary] ([Pranay Sarepaka breakdown](https://pranaysarepaka.substack.com/p/royal-match-breakdown-part-1))
- During the FTUE the game takes you to the upgrade screen automatically when you can afford an upgrade, and shows the Play button otherwise, so you don't hunt through menus. [Secondary] ([Funovus](https://funovus.com/blogs/royal-match-dominates-match-3-what-can-all-designers-learn))
- Social features (teams) are gated to around level 45, per an App Store reviewer. [Secondary, weak] ([App Store listing reviews](https://apps.apple.com/us/app/royal-match/id1482155847))
- The sibling game Royal Kingdom skips basic tutorials and puts obstacles in level 1, on the assumption that players already know match-3. [Secondary] ([Deconstructor of Fun, 2023](https://www.deconstructoroffun.com/blog/2023/05/09/royal-kingdom-will-it-usurp-the-throne))
- **[Unverified]** When it asks for a name, a Facebook connection, or notification permission. No public teardown documents it. Commonly believed: no name or account before level 1, and an optional Facebook connect later.

**Candy Crush (King)**
- No forced sign-up. You play level 1 on the device right away. A registration prompt comes later, and the payoff for connecting is comparing scores with friends. These details come from a Leanplum teardown of the sibling game Candy Crush Jelly Saga. [Secondary] ([Leanplum](https://leanplum.com/?p=15778))
- You can finish the whole game without connecting Facebook or a King account. The cost is that progress lives only on the device. [Secondary, community forum] ([King Community](https://community.king.com/en/candy-crush-saga/discussion/351489/how-to-play-candy-crush-without-facebook))
- Facebook's own developer guidance: prompt for login only once people "appreciate what your app has to offer enough to trust it with their information." [Primary] ([Facebook Login UX](https://developers.facebook.com/docs/facebook-login/userexperience))

**Monopoly GO (Scopely)**
- Within about two minutes of first launch a new player has rolled dice, built, attacked another board, robbed another player, and collected bonuses. The first session is designed to feel like "a party for you." [Secondary] ([Gamigion, "The First Session Is Not An Intro"](https://www.gamigion.com/?p=33158))
- The first two cities go by fast and are full of rewards. Social features show up immediately: the game suggests active strangers as friends, so new players with no friends still get a social loop. The Community Chest unlocks at 5+ friends. [Secondary] ([PocketGamer.biz deconstruction](https://www.pocketgamer.biz/feature/82065/under-the-hood-deconstructing-monopoly-go-as-it-passes-2-billion-in-revenue/))
- After the tutorial, beginner guides tell players to turn on notifications for free gifts and event reminders. That implies the ask comes after the first session, not at launch. [Secondary, weak] ([TalkAndroid guide](https://www.talkandroid.com/37581-monopoly-go-beginners-guide/))
- **[Unverified]** The exact screen order and the timing of the notification and Facebook prompts.

**Wordle / NYT Games**
- You can play Wordle without an account. A free NYT account is required to see and sync stats, and the stated benefit is cross-device sync. [Primary + Secondary] ([NYT Help Center](https://thenewyorktimeshelpcenter.helpjuice.com/360011158491-New-York-Times-Games/24611727334932-Wordle), [PC Gamer](https://pcgamer.com/games/puzzle/wordle-stats-new-york-times-account-required))
- Without an account, progress is stored on the device and can be lost. NYT uses that risk as the reason to register. [Primary] ([NYT Help Center](https://thenewyorktimeshelpcenter.helpjuice.com/360011158491-New-York-Times-Games/24611727334932-Wordle))

**Duolingo (outside games, but the best-documented experiment)**
- "Simply moving the sign-up screen back a few steps led to about a 20% increase in DAUs." Later soft-wall/hard-wall work added another 8.2% DAU. The VP of Growth also noted that hard walls perform "significantly worse" without soft walls first. [Primary interview, 2017] ([First Round Review](https://review.firstround.com/the-tenets-of-a-b-testing-from-duolingos-master-growth-hacker/))

### Pattern summary
1. Gameplay comes first. The first interaction is the game itself, with no name, account, or permission screens before it.
2. Teaching happens in play, through short contextual tips (Apple's HIG says the same; see §5).
3. The account is sold as protection ("save your progress", "sync your stats"), and only after the player has something worth saving.
4. Social features either come later (Royal Match) or are faked early with suggested strangers (Monopoly GO). Pounce's version of the second approach is house cats.

---

## 2. Social and turn-based games: Words With Friends, GamePigeon, UNO! Mobile, Board Game Arena, Chess.com (plus NYT Crossplay)

### How they get a new player into a first game

| Game | Bot | Friend | Random | Account needed? | Source |
|---|---|---|---|---|---|
| Words With Friends 2 | "Solo Challenge" vs Word Masters | Friends tab, username, Facebook | "Pick My Match" creates a game with a random player | Zynga account | [Zynga support](https://zyngasupport.helpshift.com/hc/en/63-words-with-friends-2/faq/10538-how-do-i-start-a-game) [Primary] |
| GamePigeon | Some games | Pick a contact in iMessage; the game is a message bubble | No | No account, but needs iMessage | [Lilach Bullock guide](https://www.lilachbullock.com/how-to-play-games-on-imessage/) [Secondary] |
| UNO! Mobile | Quick Play | Multiplayer, then Friends, then create a room or join with a Room ID; friend player IDs | Quick Play | Unclear | [Mattel163 FAQ](https://mattel163.com/?p=589) [Primary] |
| Board Game Arena | Not the main path | Create a table, copy the link, friends' avatars appear as they join | Public tables | Yes | [TU Delft guide](https://ch.tudelft.nl/boardgamearena-com-instructions/) [Secondary] |
| Chess.com | 100+ bots | Challenge link | Guest play: pick a skill level, then "Play as Guest" | Optional for guest play | [Chess.com guest play](https://support.chess.com/en/articles/8615312-what-is-guest-play-i-can-play-without-an-account) [Primary] |
| NYT Crossplay (2026) | Easy/medium/hard computer | Link or QR from Friends; installs via the store if missing | Skill-based "Find a Match" that may also suggest a friend or a computer | Yes, NYT account | [NYT Help: Crossplay](https://thenewyorktimeshelpcenter.helpjuice.com/crossplay-app) [Primary] |

Details worth noting:
- **Chess.com** asks for a skill level ("New to chess" maps to about 400) during sign-up, so the first match is sized to the player. [Primary] ([Chess.com create account](https://support.chess.com/en/articles/8584217-how-do-i-create-an-account)). Users complain that the self-rating mis-seeds matchmaking ([forum](https://www.chess.com/clubs/forum/view/suggestion-simpler-and-more-positive-experience-for-brand-new-players?lc=1)) [Secondary]. Lesson: in a family game, skill is better handled by bot difficulty than by matchmaking.
- **Words With Friends** has historically had no real tutorial. A reviewer of the 2014 relaunch said newcomers "must play solo for a while to get used to the interface." [Secondary] ([Yahoo review](https://uk.news.yahoo.com/words-friends-review-195521106.html)). In soft launch, the relaunch saw "20 percent better retention" than the original. [Secondary interview] ([GamesBeat](https://gamesbeat.com/after-six-months-of-testing-zynga-finally-launches-its-critical-mobile-game-new-words-with-friends))
- **NYT Crossplay**, NYT's first multiplayer game (January 2026), lets you play a computer before matchmaking, but it puts the human game behind an NYT account. [Primary] ([GamesBeat, Jan 2026](https://gamesbeat.com/why-nyt-games-is-launching-its-first-multiplayer-game-crossplay-with-a-standalone-app/))
- **GamePigeon**: the game lives in the conversation. The bubble shows whose move it is, and if the recipient doesn't have the extension, Messages offers a "Get" button or sends them to the App Store. The interactive experience requires the install. [Secondary, developer forum] ([Apple Dev Forums](https://developer.apple.com/forums/thread/66643), [Linq docs](https://docs.linqapp.com/guides/messaging/imessage-apps/))

### How they handle waiting for your friend
- **Turn timers that fit the cadence.** Crossplay gives 7 days per turn and then times out as a resignation [Primary] ([NYT Help](https://thenewyorktimeshelpcenter.helpjuice.com/crossplay-app)). Chess.com Daily lets you pick days per move and has account-wide **vacation** that pauses every game at once; new accounts start with 7 days [Primary] ([Chess.com vacation](https://support.chess.com/en/articles/8583943-how-does-vacation-work-how-much-time-do-i-get)). BGA turn-based tables often allow a day per move [Secondary] ([Tom's Guide](https://www.tomsguide.com/gaming/this-app-let-me-play-board-games-with-friends-even-when-i-was-stuck-at-home-and-its-completely-free)).
- **Many games in parallel.** WWF, Chess.com Daily, and Crossplay all expect several games at once, so there's nearly always one where it's your turn. [Primary, via the support pages above]
- **The conversation is the waiting room.** GamePigeon's bubble sits in iMessage where the family already talks, so the "your turn" signal arrives through an existing channel. [Secondary] ([Lilach Bullock](https://www.lilachbullock.com/how-to-play-games-on-imessage/))
- **Push copy matters.** Zynga's With Friends lead framed every push with the question "Is this push notification beloved?" (GDC 2012). [Secondary] ([PocketGamer.biz](https://www.pocketgamer.biz/news/38678/gdc-2012-we-ask-are-our-push-notifications-beloved-says-zynga-with-friends-vijay-thakkar/)). Duolingo's winning notification copy alone gave +5% DAU, and sending reminders 23.5 hours after the last session worked best. [Primary interview] ([First Round](https://review.firstround.com/the-tenets-of-a-b-testing-from-duolingos-master-growth-hacker/))
- **[Unverified]** Whether WWF or UNO! currently send a new player into a bot game automatically on first launch.

---

## 3. Party and room-code games: Jackbox, Kahoot, Among Us, Heads Up

| Game | Join flow | Account | Source |
|---|---|---|---|
| Jackbox | Open jackbox.tv in any browser, enter the **4-letter** room code from the TV, enter a name, Play. No install. New code every game. Players join first, then the audience. | None for players. Only the host owns the game. | [Jackbox support](https://support.jackboxgames.com/hc/en-us/articles/15794759479959-How-do-I-join-a-game) [Primary]; [teleconference guide](https://craig-edward-given.squarespace.com/blog/2020/4/29/hosting-amp-playing-jackbox-games-via-teleconferencing) [Secondary] |
| Kahoot | Three equal paths: type the PIN at kahoot.it or in the app, tap a join link, or **scan a QR code**. Then a nickname, or an optional **nickname generator** (up to 3 spins from about 800 two-word names). | None unless the host turns on "player identifier." | [Kahoot support](https://support.kahoot.com/hc/articles/360039890713) [Primary]; [Kahoot blog 2017](https://kahoot.com/blog/2017/11/09/generate-funny-nicknames-players-live-kahoots/) [Primary]; [player identifier](https://support.kahoot.com/hc/articles/360036178314) [Primary] |
| Among Us | Host makes a private lobby and the code appears there. Friends go to Online, enter the code, and join. The code grew from **4 to 6 letters** in September 2020 to fit more rooms. No friends list. | None | [Twinfinite](https://twinfinite.net/guides/among-us-how-to-play-with-friends/), [xboxplay.games](https://xboxplay.games/among-us/-how-to-fix-6-digit-and-letters-code-error-10819) [Secondary] |
| Heads Up | One device, passed around: pick a deck, hold the phone to your forehead, countdown, tilt down for correct, tilt up to pass. Nobody else joins on a device. | None | [App Store listing](https://apps.apple.com/us/app/heads-up/id623592465) [Primary]; [AppSamurai](https://appsamurai.com/blog/mobile-app-success-story-heads-up/) [Secondary] |

Patterns:
- **Code, then name, then play.** Two fields, no account, no install (Jackbox, Kahoot). The name field is the only identity step.
- **The code is shown big on the host screen**, so it can be read aloud across a room. Kahoot adds QR codes and links for people who aren't in the same room.
- **Kid-safe naming.** Kahoot's generator exists because typed names get abused in classrooms. A blocked-word filter swaps bad names for neutral words, and hosts can kick players. [Primary] ([Kahoot, 2019](https://kahoot.com/blog/2019/03/08/tips-keep-kahoot-nicknames-appropriate/))
- **Family-safe defaults.** Since Party Pack 9, Jackbox puts a "Family-Friendly" toggle on the home screen that applies to every game. It filters prompts but not what players type; a separate profanity filter handles that. [Primary] ([Jackbox safety](https://www.jackboxgames.com/blog/safety-and-moderation-streaming-jackbox-games), [Jackbox ratings FAQ](https://support.jackboxgames.com/hc/en-us/articles/15794785491351-Are-your-games-family-friendly-What-are-they-rated))
- **Pass-and-play is a legitimate mode** (Heads Up, BGA "hotseat friend" [Primary] [BGA news](https://en.boardgamearena.com/news?id=424)). A family at one table may not want four phones.

---

## 4. Invite-link mechanics

### Deferred deep linking (link, App Store, install, land in the friend's room)
- **How it works:** the link opens the app if it's installed. Otherwise it goes to the store, and on **first open** the SDK fetches the pending link data and routes the player to the content. You can't run code during the App Store install, so the context has to be recovered on first launch. [Primary] ([Branch help: deep linking](https://help.branch.io/docs/deep-linking), [Branch: deferred deep linking on iOS](https://www.branch.io/resources/blog/how-to-set-up-deferred-deep-linking-on-ios/))
- **The iOS problem:** IP and fingerprint matching broke under Private Relay and ATT. Branch's **NativeLink** instead copies a token to the clipboard on the web landing page and reads it on first open. Since iOS 16 that read triggers a system paste prompt. [Primary] ([Branch NativeLink docs](https://help.branch.io/docs/nativelink-deferred-deep-linking))
- **Firebase Dynamic Links shut down on 25 August 2025**, with no Google replacement. Universal Links handle the app-installed case but not deferred routing. [Secondary] ([Pragmatic Engineer](https://blog.pragmaticengineer.com/google-shutting-down-firebase-dynamic-links/), [AppsFlyer](https://www.appsflyer.com/blog/mobile-marketing/fdl-deprecation-deep-linking/))
- **Implication for Pounce:** a 5-character code is your best deferred-link fallback. The web landing page should show the code in large type, copy it on tap (the NativeLink idea without a vendor), and the app's first screen should offer "Have a table code?" or read the pasteboard after the user taps a paste control. Nothing breaks if attribution fails.

### App Clips (instant play without a full install)
- **Apple supports demo App Clips.** An App Clip is "a lightweight version of your app ... or gives people a way to try a demo version of your app." [Primary] ([Apple: Choosing the right functionality](https://developer.apple.com/documentation/appclip/choosing-the-right-functionality-for-your-app-clip))
- **Size:** 10 MB (iOS 15 and earlier), 15 MB (iOS 16), and **up to 100 MB on iOS 17+** for digital-only invocations or with the App Clip **demo link**. Games can pull extra assets with Background Assets while the player sets up. [Primary] (same page; [Creating an App Clip](https://developer.apple.com/documentation/appclip/creating-an-app-clip-with-xcode))
- **Invocation from Messages:** a link shared in Messages (as a text message) shows an **App Clip card** with a header image, a subtitle of up to 56 characters, a title of up to 30, and an action verb. The default link format is `https://appclip.apple.com/id?=<bundle_id>&key=value`, so it can carry a table code. The demo link can't carry URL parameters. [Primary] ([Configuring App Clip experiences](https://developer.apple.com/documentation/appclip/configuring-the-launch-experience-of-your-app-clip))
- **Handoff:** installing the full app **replaces** the clip. Data moves through an App Group container, shared UserDefaults, the keychain (iOS 15.4+), or Sign in with Apple. Apple says: "Don't require users to log in to their account again." [Primary] ([Sharing data between App Clip and app](https://developer.apple.com/documentation/appclip/sharing-data-between-your-app-clip-and-your-full-app))
- **Notifications** in a clip are ephemeral, up to 8 hours after each launch, and limited to transactional uses. [Primary] ([Apple: Enabling notifications in App Clips](https://developer.apple.com/documentation/appclip/enabling-notifications-in-app-clips)). That fits a live game but not async play over days.
- **Rules:** all clip functionality must also be in the main app, and clips can't show ads (Guideline 2.5.16). [Primary] ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/))
- **[Unverified]** I found no shipping example of a multiplayer game using an App Clip to join a friend's room. Phoenix 2 used one for a single-player demo level ([AppTweak](https://www.apptweak.com/en/aso-blog/what-are-app-clips-and-how-to-use-them)) [Secondary]. Pounce would be early here.

### Web fallback pages
- If the app isn't installed, a Universal Link opens the web page, which makes that page the fallback. Add `<meta name="apple-itunes-app" content="app-id=…, app-argument=…">` for a Smart App Banner. Facebook and Instagram in-app browsers often block Universal Links. [Secondary] ([Nimble guide](https://nimblehq.co/blog/guideline-ios-universal-links-android-app-links), [Airbridge](https://www.airbridge.io/en/blog/your-universal-links-open-in-safari-instead-of-the-app))
- Jackbox and Kahoot go further: the web page is the game. That's the most extreme form of "no install needed." [Primary] (sources in §3)

### The invite message and preview card
- In Messages, link previews come from Open Graph tags: **og:title** (short and specific, no site branding; use og:site_name for the brand) and **og:image** (at least 900 px wide, no text in the image). Previews don't run JavaScript or follow meta redirects, so the metadata has to be server-rendered. Pages behind a login should still describe the destination ("Sign In" is not a title). [Primary] ([Apple TN3156](https://developer.apple.com/documentation/technotes/tn3156-create-rich-previews-for-messages))
- Implication: render per-table metadata on the server, for example og:title "Mom saved you a seat · Table K7Q2M" with an image of the table and its cats.

### Invite rewards
- **Monopoly GO:** the Friends tab has an orange link button and a blue Messenger button. A progress bar fills as invitees start playing. Guides report 25 dice for the first Facebook invite and milestones up to about 150–180 dice plus a token at 10 friends; figures vary by guide. [Secondary] ([GameSkinny](https://www.gameskinny.com/tips/how-to-send-and-share-your-monopoly-go-link/), [PocketGamer](https://www.pocketgamer.com/monopoly-go/free-rolls)). The structural lever is the **Community Chest**, which needs 5+ friends and rewards helpers even when they aren't playing. [Secondary] ([PocketGamer.biz](https://www.pocketgamer.biz/feature/82065/under-the-hood-deconstructing-monopoly-go-as-it-passes-2-billion-in-revenue/))
- **Clash Royale:** you invite through a shareable link or QR code (Social, then Invite Friend). I found **no standing per-invite reward**, only time-limited events such as a November 2024 event that awarded 5,000 season tokens for 2v2 battles with invited friends. [Secondary] ([techstory](https://techstory.in/how-to-add-a-friend-on-clash-royale/), [Sportskeeda](https://sportskeeda.com/mobile-games/how-get-free-5000-season-tokens-clash-royale)). **[Unverified]** whether any always-on invite bonus exists.
- **Board Game Arena** gave free Premium for invites ("Invite your friends and get Premium for free"). [Primary] ([BGA news](https://en.boardgamearena.com/news?id=424))
- Caution for Pounce: incentivized invites aimed at kids are a family-trust risk, and Kids Category apps can't show "purchasing opportunities, or other distractions" outside a parental gate (Guideline 1.3). Reward the **family table**, not the individual inviter.

---

## 5. Notification permission and Sign in with Apple timing

### Notifications (Apple's rules)
- "Avoid requesting permission at launch unless the data or resource is required for your app to function." Ideally wait "until people actually use an app feature that requires access." [Primary] ([HIG: Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy))
- Apple's own example is a reminder app asking "after the person schedules a first task", which it calls a better experience than asking on first launch. [Primary] ([Apple: Asking permission to use notifications](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications))
- **Pre-alert screens are allowed with strict rules:** one button only, labeled "Continue" or "Next" (never "Allow"), and no close or cancel option. [Primary] ([HIG: Privacy, pre-alert screens](https://developer.apple.com/design/human-interface-guidelines/privacy))
- **Provisional authorization** delivers notifications quietly to Notification Center with no prompt, and the user keeps or turns them off from there. [Primary] ([Apple UserNotifications docs](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications))
- Push can't be required for the app to work, and marketing pushes need explicit opt-in (Guideline 4.5.4). [Primary] ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/))
- **For Pounce:** the moment it makes sense is right after the player's first async move ("It's Grandpa's turn. Want a tap when it's yours?"). For live play, ask when the player leaves a table where it isn't their turn.

### Sign in with Apple and deferred accounts
- "**Delay sign-in as long as possible.** People often abandon apps when they're forced to sign in before doing anything useful." "Ask people to sign in only in exchange for value," for example to sync data. [Primary] ([HIG: Sign in with Apple](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple))
- "As soon as Sign in with Apple completes, welcome people to their new account ... don't delay the experience by asking for information that isn't required." [Primary] (same)
- App Review 5.1.1(v): "If your app doesn't include significant account-based features, let people use it without a login." [Primary] ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/))
- Apple's onboarding HIG: "Postpone nonessential setup flows," "Teach through interactivity," and "Prefer letting people experience your app ... before prompting them for ratings or purchases." [Primary] ([HIG: Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding))
- Evidence on size: Duolingo saw about +20% DAU from moving sign-up later. [Primary interview] ([First Round](https://review.firstround.com/the-tenets-of-a-b-testing-from-duolingos-master-growth-hacker/)). NYT and King both use "you could lose your progress" as the reason to create an account (see §1).

---

## 6. Published funnel benchmarks

| Metric | Figure | Source and year | Confidence |
|---|---|---|---|
| D1 retention, top 25% of mobile games | 26.5–27.7% (2024 data; down from 28–29% in 2023) | [GameAnalytics 2025 Mobile Gaming Benchmarks](https://www.gameanalytics.com/reports/2025-mobile-gaming-benchmarks), summarized by [GameDev Reports, Feb 2025](https://gamedevreports.substack.com/p/gameanalytics-mobile-gaming-benchmarks) | Primary report, read via summary |
| D1, top 25%, iOS vs Android | iOS 31–33%, Android 25–27% | same | same |
| D1, bottom 25% | 10–11.5% | same | same |
| D7, median | 3.4–3.9% (top 25%: 7–8%) | same | same |
| Session length | Median 5–6 min; top 25% 8–9 min; about 4 sessions per day | same | same |
| Genre note | Board, card, puzzle and casino are the best genres for medium- and long-term retention (no numbers in the text) | same | same |
| D1, gaming median (Adjust) | About 29% gaming and social; iOS gaming D1 27%, D30 8% (2024) | Adjust, April 2024, via [getstream](https://getstream.io/blog/app-retention-guide/) and [Adjust blog](https://www.adjust.com/blog/what-makes-a-good-retention-rate/) | **Secondary**; the Adjust page returned 429 so I couldn't verify directly |
| Delayed sign-up effect | About +20% DAU | Duolingo, [First Round 2017](https://review.firstround.com/the-tenets-of-a-b-testing-from-duolingos-master-growth-hacker/) | Primary interview |
| Notification copy effect | +5% DAU from copy alone | same | Primary interview |
| WWF relaunch soft-launch retention | +20% vs original | Zynga's Jonathan Knight, [GamesBeat 2014](https://gamesbeat.com/after-six-months-of-testing-zynga-finally-launches-its-critical-mobile-game-new-words-with-friends) | Secondary interview |
| iOS push opt-in, games | Hypercasual about 23%, action about 44%; all-industry iOS about 56% | [Pushwoosh 2025](https://www.pushwoosh.com/blog/push-notification-benchmarks/); [Batch 2025](https://batch.com/ressources/etudes/benchmark-notifications-push-crm-mobile) | Vendor benchmarks |
| Tutorial completion | "65–80% acceptable, <65% critical" is a widely repeated rule of thumb with **no primary source**. An academic case (Quantum Moves) had 60% finish the tutorial. | [arXiv 1506.08761](https://arxiv.org/pdf/1506.08761) | Weak |
| Time to first game | "Core gameplay within 60 seconds" is a common rule of thumb; Monopoly GO reaches all its core verbs in about 2 minutes | [Gamigion](https://www.gamigion.com/?p=33158) | Weak / anecdotal |
| Invite conversion and K-factor | Vendor blogs give 8–45% click-to-install and K of 0.3–0.6 for games. Playio says there's "effectively no reliable public benchmark" and K>1 is rare. | [Playio](https://blog.playio.co/viral-coefficient-organic-uplift-mobile-games), [Tenjin](https://tenjin.com/glossary/k-factor/) | **Unreliable**; use your own data |
| Social features and retention | First-week social engagement predicted D30 retention in one of two F2P mobile games studied; adding social features "does not necessarily" improve retention | [Univ. of Jyväskylä thesis, 2019](https://jyx.jyu.fi/handle/123456789/66822) | Academic, small sample |

**Not found:** a published tutorial drop-off benchmark from a major analytics vendor, and any public invite-conversion benchmark for games. Instrument these yourself: install → first table joined → first move → first game finished → D1.

---

## 7. Family and kids specifics

- **Apple Kids Category (Guideline 1.3):** no links out, purchases, or "other distractions" except "behind a parental gate"; no sending PII or device info to third parties; and "should not include third-party analytics or third-party advertising." This keeps applying in later updates even if you leave the category. [Primary] ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/); [Apple 2019 news](https://developer.apple.com/news/?id=06032019j))
- **Toca Boca**: a "For Parents" area behind a hold-the-button or math gate. The gate guards the store and settings, not play. [Secondary] ([Screenwise](https://screenwiseapp.com/guides/toca-boca-jr-app), [Bitdefender](https://www.bitdefender.com/en-us/blog/hotforsecurity/is-your-child-playing-toca-boca-world-heres-what-you-should-know)). **[Unverified]** from Toca's own documentation.
- **PBS KIDS Games**: no login, no usernames, fully anonymous play. A grown-ups section manages storage, Wi-Fi use, and captions. [Secondary] ([Bark review](https://www.bark.us/app-reviews/apps/pbs-kids-games/), [PBS announcement](https://www.pbs.org/about/blogs/news/new-app-offers-free-access-to-pbs-kids-games-anytime-anywhere))
- **Duolingo ABC**: designed for the parent to set up and then hand to the child. Parents give the child's age, profiles support several learners, no account is needed to start, and there are no ads or IAP. [Secondary] ([Common Sense privacy review](https://privacy.commonsense.org/evaluation/Duolingo-ABC---Learn-to-Read), [9to5Mac](https://9to5mac.com/2020/03/26/duolingo-abc-learn-to-read-ios-free-app/))
- **Apple Declared Age Range API (iOS 26)** returns an age band (under 13, 13–15, 16–17, 18+) rather than a birthdate. Parents in Family Sharing choose whether to share it always, per request, or never. iOS 26.2 added PermissionKit's "significant change" parental consent. [Primary + Secondary] ([Apple API docs](https://developer.apple.com/documentation/declaredagerange/agerangeservice), [Apple Newsroom, June 2025](https://www.apple.com/newsroom/2025/06/apple-expands-tools-to-help-parents-protect-kids-and-teens-online/), [MacRumors](https://www.macrumors.com/2025/11/04/ios-26-2-texas-age-verification-law/)). Not available before iOS 26 and there's no fallback API ([Apple forums](https://developer.apple.com/forums/thread/809076)).
- **COPPA amendments** took effect 23 June 2025, with full compliance due 22 April 2026. Sharing a child's data with third parties now needs **separate** parental consent unless it's integral to the service. [Secondary, law-firm summaries] ([Davis Polk](https://www.davispolk.com/insights/client-update/ftc-prioritizes-coppa-enforcement-new-compliance-obligations-take-effect), [Finnegan](https://www.finnegan.com/en/insights/articles/coppas-amended-rule-is-now-in-full-effect-what-operators-need-to-know.html))
- **Kahoot and Jackbox** (see §3): generated nicknames and a family-friendly toggle are the conversion-friendly ways to keep kids safe in shared rooms. They add no extra steps and keep strangers' typed text out.
- **Apple Arcade titles**: **[Unverified]** I didn't find a source documenting a specific Arcade family title's age-gate flow. Arcade's general model (no ads, no IAP, Family Sharing) removes most of the reasons for gates.

**Pattern:** the grown-up sets things up once (household, kid profiles, age), then hands over the device. Kids never meet an account wall. Gates sit only around purchases, outbound links, account changes, and anything social with strangers. A gate is a quick adult task (hold or math), not a form.

---

## 8. Top 12 patterns, ranked by likely impact for a family turn-based game

1. **The invite link drops the guest straight into a seat at the host's table, asking only for a name or an avatar pick, with no account.** This is the Jackbox and Kahoot model: code, name, play. *Sources:* [Jackbox support](https://support.jackboxgames.com/hc/en-us/articles/15794759479959-How-do-I-join-a-game), [Kahoot support](https://support.kahoot.com/hc/articles/360039890713).
2. **Carry the table through the install** with a deferred deep link: a code token on the web landing page (clipboard or paste control), and the 5-character code as a fallback that always works on the first screen. Don't depend on Firebase Dynamic Links (shut down August 2025). *Sources:* [Branch NativeLink](https://help.branch.io/docs/nativelink-deferred-deep-linking), [Branch deferred deep linking](https://help.branch.io/docs/deep-linking), [Pragmatic Engineer on FDL](https://blog.pragmaticengineer.com/google-shutting-down-firebase-dynamic-links/).
3. **A brand-new solo player is in a real game against house cats within about 60 seconds**, with no tutorial wall: teach with in-play tips, make the tutorial optional, and keep the first hand winnable. *Sources:* [Apple HIG Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding), [Gamigion on Monopoly GO and Clash Royale](https://www.gamigion.com/?p=33158), [NYT Crossplay computer opponents](https://thenewyorktimeshelpcenter.helpjuice.com/crossplay-app).
4. **No account until there's value to protect.** Offer Sign in with Apple after the first finished game, framed as "keep your family's tables on every device," and welcome the player straight back into play. *Sources:* [HIG Sign in with Apple](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple), [Duolingo +20% DAU](https://review.firstround.com/the-tenets-of-a-b-testing-from-duolingos-master-growth-hacker/), [App Review 5.1.1(v)](https://developer.apple.com/app-store/review/guidelines/).
5. **Ask for notifications right after the player's first move in a game where someone else is up next.** Use a single-button pre-alert ("Continue"); consider provisional authorization for kids' devices. *Sources:* [HIG Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy), [Apple: Asking permission](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications).
6. **Make the invite preview card personal and server-rendered:** og:title names the person and table, og:image is at least 900 px and has no text in it, and the metadata works without JavaScript. *Source:* [Apple TN3156](https://developer.apple.com/documentation/technotes/tn3156-create-rich-previews-for-messages).
7. **Never leave a player waiting with nothing to do.** House cats fill empty seats, and a cat can take a turn when the game is live; there's always another table where it's your turn; and async turn timers come with a family-sized "pause" (vacation). *Sources:* [Chess.com vacation](https://support.chess.com/en/articles/8583943-how-does-vacation-work-how-much-time-do-i-get), [Crossplay 7-day turns](https://thenewyorktimeshelpcenter.helpjuice.com/crossplay-app), [Monopoly GO suggested friends](https://www.pocketgamer.biz/feature/82065/under-the-hood-deconstructing-monopoly-go-as-it-passes-2-billion-in-revenue/).
8. **Grown-up sets up once, then hands the device to the kid.** Household and kid profiles are created by the parent, age comes from the Declared Age Range API on iOS 26+, and parental gates sit only around purchases, links, and account settings. *Sources:* [Duolingo ABC (Common Sense)](https://privacy.commonsense.org/evaluation/Duolingo-ABC---Learn-to-Read), [Apple Declared Age Range](https://developer.apple.com/documentation/declaredagerange/agerangeservice), [Guideline 1.3](https://developer.apple.com/app-store/review/guidelines/).
9. **A web fallback page for every table link:** the code in large type, a tap-to-copy button, an App Store button and Smart App Banner, and "who's at the table." It also catches Facebook and Instagram in-app browsers that block Universal Links. *Sources:* [Nimble Universal Links guide](https://nimblehq.co/blog/guideline-ios-universal-links-android-app-links), [Airbridge](https://www.airbridge.io/en/blog/your-universal-links-open-in-safari-instead-of-the-app).
10. **Kid-safe identity by default:** generated or picked names and avatars instead of free text for kids, plus family-friendly content on by default. *Sources:* [Kahoot nickname generator](https://kahoot.com/blog/2017/11/09/generate-funny-nicknames-players-live-kahoots/), [Kahoot name filter](https://kahoot.com/blog/2019/03/08/tips-keep-kahoot-nicknames-appropriate/), [Jackbox family-friendly](https://www.jackboxgames.com/blog/safety-and-moderation-streaming-jackbox-games).
11. **An App Clip so invited guests can play without the full install:** a table link in Messages shows an App Clip card; on iOS 17+ the clip can be up to 100 MB for digital invocation; the seat and Sign in with Apple carry over through an App Group when they install. It's high effort, and I found no multiplayer precedent. *Sources:* [Apple App Clip functionality and sizes](https://developer.apple.com/documentation/appclip/choosing-the-right-functionality-for-your-app-clip), [Configuring App Clip experiences](https://developer.apple.com/documentation/appclip/configuring-the-launch-experience-of-your-app-clip), [Sharing data with full app](https://developer.apple.com/documentation/appclip/sharing-data-between-your-app-clip-and-your-full-app).
12. **Reward the table, not the recruiter:** a visible progress bar as invited family members play their first game, unlocking a shared cosmetic (a new cat or table cloth), with no currency and no kid-targeted incentives. *Sources:* [Monopoly GO invite milestones (GameSkinny)](https://www.gameskinny.com/tips/how-to-send-and-share-your-monopoly-go-link/), [Community Chest 5-friend gate (PocketGamer.biz)](https://www.pocketgamer.biz/feature/82065/under-the-hood-deconstructing-monopoly-go-as-it-passes-2-billion-in-revenue/), [BGA invite-for-Premium](https://en.boardgamearena.com/news?id=424).

---

## Couldn't verify (check by fresh-installing)
- The exact first-launch screen order and notification/Facebook prompt timing for Royal Match, Candy Crush, and Monopoly GO.
- Whether Words With Friends or UNO! Mobile currently auto-start a bot game on first launch.
- Whether GamePigeon recipients without the app can see the game state or only an install prompt (sources conflict).
- Any standing per-invite reward in Clash Royale.
- A multiplayer game that uses an App Clip to join a friend's room.
- Toca Boca's gate mechanics from Toca's own documentation, and any Apple Arcade family title's age-gate flow.
- Adjust's 2024 gaming D1 figure on Adjust's own page (rate-limited; cited secondhand).
