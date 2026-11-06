# Parent consent for kittens (daily habit PR 9): design addendum

An addendum to `2026-11-04-daily-habit-design.md` §14.1 ("Later: parent consent") and §15 row 9. This is a design that follows the rules as researched, not legal advice.

## 1. What Apple actually gives us (researched 2026-11-05)

| Question | Answer | Source |
|---|---|---|
| Can an app read the Apple family: who the organizer or parent is, who the children are? | **No.** There is no family roster API. Everything nearby returns a flag or a system-run approval, never people. | StoreKit `ownershipType`, `appTransactionID` (unique per family member, not linkable); Family Controls returns only an authorization status and needs a reviewed entitlement for parental-controls apps |
| What does Declared Age Range tell us about a guardian? | That one exists, nothing more: `ageRangeDeclaration == .guardianDeclared` means "a parent, guardian, or Family Organizer set the age range". `activeParentalControls` can include `.communicationLimits`. `.confirmed` (26.5+) means the age was checked with a card or ID. | developer.apple.com/documentation/declaredagerange |
| Can a parent approve who a kitten plays with through Apple? | **Partly, through PermissionKit "ask to communicate".** On the kitten's device the app builds a `PermissionQuestion<CommunicationTopic>` naming a person by a `.custom` handle (our player id) with an action such as `.connect`. The parent answers in Messages, and the kitten's app is woken in the background with the approval or denial. `CommunicationLimits.current.knownHandles(in:)` lists who is approved. | developer.apple.com/documentation/permissionkit; WWDC25 session 293 |
| Limits of PermissionKit | It works only for a child in a Family Sharing group with Screen Time Communication Limits on. Otherwise it returns a default answer or `AskError.communicationLimitsNotEnabled` / `.notAvailable`, and it always throws for adults. There is no "receive notifications" action, and Apple doesn't document revoking a communication approval. | `AskError`; WWDC25 293 |
| Does an Apple approval count as COPPA verifiable parental consent? | **No FTC source says so.** Consent through a platform can count only if it is reasonably calculated to confirm the person is the parent, and we must still send our own direct notice (FAQ I.10). PermissionKit approves *contacts*; it doesn't verify the parent or carry our notice. | ftc.gov COPPA FAQ I.10; 16 CFR 312.5 |
| Which consent methods can we use ourselves? | §312.5(b)(2) lists: signed form, card with a transaction, toll-free or video call with staff, ID checked against databases, knowledge-based questions, photo ID with face match, **email plus**, and **text plus** (new in 2025). Email plus and text plus are allowed only when the child's personal information is never disclosed. | eCFR 16 CFR 312.5(b)(2), as of 2026-11-01 |
| Can turn pushes run on notice alone? | Possibly, under the multiple-contact exception (§312.5(c)(4)). That needs a notice to the parent with an opt-out, and the token must not be combined with other personal information. Pounces from other people are contact *by others*, which needs full consent. | §312.5(c)(4); FAQ J.9, D.12 |
| State app-store laws | Texas SB 2420 has been in force since 4 June 2026. Utah moved developer duties to 6 May 2027 (HB 498) and Louisiana to 1 July 2027 (HB 977). Letting kittens receive pushes changes the data we collect, so it is a **significant change**. Apple collects that consent on the parent's device through `PermissionQuestion(significantAppUpdateTopic:)`; withdrawal arrives as a `RESCIND_CONSENT` App Store Server Notification. That is state-law consent, not COPPA consent. | developer.apple.com/support/age-assurance; capitol.texas.gov SB 2420 |

**So, plainly:** Family Sharing can't tell Pounce who a kitten's parents are. It can do two useful things:
- carry a parent's approval of *who* the kitten plays with, when the kitten has Communication Limits on;
- carry the state-law significant-change consent.

COPPA consent itself has to be our own: a direct notice, and a listed method.

## 2. The consent model

Three layers, each doing what it's good for.

### Layer 1: the link (ours)
- A **signed-in adult** (band `adult`, Sign in with Apple) links a kitten's device to their account. The steps:
  1. On the kitten's device, the gear sheet shows a bell with a lock and a six-digit numeral code in the room-code style. The code lasts 10 minutes and is used once.
  2. On the parent's device: gear sheet, then Kittens, then plus, then the keypad. The parent enters the code.
- The server records `consents[kittenPlayer] = { parent: playerId, state: "pending" }`.
- One kitten can have more than one linked parent. Any one of them can consent or revoke.
- Household kittens (pass-and-play people on the parent's own phone) need nothing new. Their pushes already go to the parent's device (§14.1).

### Layer 2: verifiable parental consent (ours, text plus by Twilio Verify; D1, D6)
- On the parent's device, the parent reads the **direct notice**. It is a short page from the server at `/privacy/kitten-notice`, with the §312.4(c) contents: what we collect (a push token and the people the kitten plays with), why, that nothing is shared, how to revoke, and a link to the privacy policy.
- The parent then enters a mobile number (**text plus**, D1). It is collected only for consent and kept only while consent lasts.
- Twilio Verify texts that number a six-digit code (D6). The parent types it on the app's numeral keypad, and Verify's `approved` flips the state to `consented`.
- 24 to 48 hours later, between 10:00 and 20:00 where the parent is, a **push to the parent's own devices** says what they allowed, with a Revoke button (the "plus", D6). If no device of theirs accepts it within a day, consent ends.
- This works because a kitten's information is never disclosed: the name is generated, nothing is public, and there are no strangers. That is the condition for text plus.

### Layer 3: who may reach the kitten (Apple where it works, ours otherwise)
- **With Family Sharing and Communication Limits** (Declared Age Range shows `.communicationLimits`):
  - When someone new sits with the kitten or pounces them, the kitten's app asks with PermissionKit: a `CommunicationTopic` with `.connect`, the person's name and cat as `PersonInformation`, and handle `.custom(playerId)`.
  - The parent approves in Messages, and the kitten's app reports the approved handles to the server.
  - Apple's list is the authority; the server mirrors it.
- **Otherwise:** the parent picks approved people on their own device, under Kittens, then the kitten's cat, with a toggle for each person the kitten plays with.
- Either way, the server keeps `approved[kitten] = Set<playerId>`. Pushes and pounces to the kitten pass only from players in that set.

### What consent unlocks for a kitten's own device
- A push token is stored and used.
- **"Your move"** pushes for tables where every other human seat is an approved player.
- **Pounces** from approved players.
- A **fixed-time daily reminder**, off by default. Learned timing stays off.
- Still off: Messages share links out, widget push, the live table, and sign-in.
- Widget push and the live table could follow later under the same consent, but they aren't in this PR.

### Revocation
Any of these turns the kitten back to today's no-push behavior at once. The server deletes the kitten's push tokens, keeps the gameplay, and the kitten's device drops its token on the next launch.
- A linked parent taps revoke on their device.
- The parent taps Revoke on the confirmation push (D6). (Text plus's revoke link and STOP reply went with Verify.)
- The confirmation push reaches none of the consenting parent's devices within a day.
- A `RESCIND_CONSENT` notification arrives for that app transaction.
- The kitten's player is deleted, including the 90-day inactivity deletion.
- Declared Age Range reports the kitten turned 13. The consent is then no longer needed, and the record is deleted.

### State-law significant change
- The release that turns kitten pushes on is a significant change. On a device where `requiredRegulatoryFeatures` contains `.significantAppChangeRequiresParentalConsent`, the kitten's app asks through `SignificantAppUpdateTopic` before Layer 1.
- PR 2's `SignificantChangeGate` already does this for the accounts release; this reuses it with a new description.
- Where that consent is required and the answer is a denial, the lock stays.

### What the kitten sees (no words)
- The bell with a padlock and the six numerals to show a grown-up.
- A sleeping bell while pending.
- After consent, the normal bell.
- In the pounce sheet, people who aren't approved show with a small padlock and can't be pounced.
- A PermissionKit ask shows Apple's own sheet.

### What the parent sees
- **Kittens** in the gear sheet, for signed-in adults only.
- For each kitten: their cat, the consent state (pending, waiting for the code, on, and on with a check once the confirmation push reached them), a toggle per person, and revoke.
- The notice page and the phone number field. Those are the only words, and they are legal text, as with the privacy page. The code is numerals on a keypad, with pictures for another code and another number.
- The confirmation push, with the kitten's name and a Revoke button (legal text, like the notice).

## 3. Server and flags
- New `CONSENT` flag. It requires `NOTIFY`, and it is off in production until JD turns it on.
- New storage: a `Consents` record per kitten player, holding linked parents, state, the parent's phone number (deleted when consent ends), and the approved set.
- New code index for the link codes.
- New routes:
  - `POST /v1/kittens/link-code` (kitten device);
  - `POST /v1/kittens/link` (parent);
  - `PUT /v1/kittens/{player}/approved`;
  - `POST /v1/kittens/{player}/consent` (phone number; Twilio Verify texts a code);
  - `POST /v1/kittens/{player}/consent/check` (the code) and `/consent/resend` (D6);
  - `DELETE /v1/kittens/{player}/consent`;
  - an App Store Server Notifications endpoint for `RESCIND_CONSENT`, verified by Apple's signed JWS.
- `DeviceIndex.push` changes:
  - today a kitten device is refused outright;
  - with consent, it allows the kinds listed above, from senders in the approved set.

## 4. Decisions (JD, 2026-11-05)
- **D1, consent method: text plus (JD).**
  - The parent enters a mobile number on their own device.
  - ~~The server texts the notice link with a one-time confirm, and 24 to 48 hours later a second text ("You allowed this. Reply STOP or tap to revoke").~~ Replaced by D6: a code by Twilio Verify, and the second contact is a push to the parent's own devices.
  - The number is kept only while consent lasts, and is deleted when consent ends.
  - Layer 2 above reads "text" wherever it says "email". Email plus is not built.
  - **Provider: Twilio (call).** It's the standard choice and works from a Worker with plain HTTPS and basic auth. It's optional exactly like the APNs key: without the secrets, consent can't finish and nothing is sent.
  - ~~**Secrets JD creates:** `PLAY_API_TWILIO_ACCOUNT_SID`, `PLAY_API_TWILIO_API_KEY_SID`, `PLAY_API_TWILIO_API_KEY_SECRET`, `PLAY_API_TWILIO_MESSAGING_SERVICE_SID`. US texting also needs toll-free verification or A2P 10DLC registration.~~ See D6.
- **D6, Twilio Verify instead of Programmable Messaging (JD, 2026-11-05).** So Pounce needs no phone number of its own and no A2P 10DLC or toll-free registration: Verify sends from Twilio's own pre-registered senders.
  - **The code.** `POST https://verify.twilio.com/v2/Services/{VerifyServiceSid}/Verifications` with `To` and `Channel=sms`; the parent types the six digits on the app's keypad; `POST .../VerificationCheck` with `To` and `Code`, and `status == "approved"` is consent. Basic auth with the API key.
  - **Only Verify's message.** Verify sends only its own code text ("Your Pounce verification code is: …"); free text and links need a custom template that takes 2 to 4 weeks. So nothing of ours goes by text: no link, no confirm page, no second text, and no STOP to handle.
  - **The plus is a push.** 24 to 48 hours after consent, inside 10:00–20:00 local, an alert to the consenting parent's own devices, in a new category with a Revoke button. A tap opens the Kittens panel on that kitten, which then shows consent as confirmed. If no device of theirs accepts it within a day, consent ends (as text plus's undeliverable second text did).
  - **Judgment call (counsel to confirm).** 16 CFR 312.5(b)(2) lists the confirmatory contact for text plus as an example ("such as"), not a required channel. A push to the parent's own signed-in device, which the parent can act on at once, is a confirmatory contact after consent, but whether it qualifies as the "plus" is for counsel to confirm. If it doesn't, the second contact needs Verify's custom template (2 to 4 weeks) or a Messaging number with 10DLC.
  - **Secrets JD creates:** `PLAY_API_TWILIO_ACCOUNT_SID`, `PLAY_API_TWILIO_API_KEY_SID`, `PLAY_API_TWILIO_API_KEY_SECRET`, `PLAY_API_TWILIO_VERIFY_SERVICE_SID`. All or none. No phone number, Messaging Service, webhook or 10DLC.
  - **Twilio's copy of the number.** Verify holds it with the verification while the code lasts, and its own records keep it after that under Twilio's policy (its API reference gives the field a 30-day minimum retention). The notice and `/privacy` say so.
- **D2, scope: turn pushes and pounces from approved people (JD).** Plus the optional fixed-time reminder.
- **D3, approvals: Apple's PermissionKit when the kitten has Communication Limits, otherwise the parent's own list in Pounce (JD).**
- **D4, production: `CONSENT` is on at merge (JD).** Real kittens can consent as soon as the Twilio Verify secrets exist, without a legal review of the notice first. The notice text is a draft for JD to check.
- **D5, App Store Server Notifications (portal item for JD).** Receiving `RESCIND_CONSENT` needs the production notification URL set in App Store Connect:
  1. App, then App Information, then App Store Server Notifications.
  2. Production Server URL: `https://play.conleychaos.com/v1/appstore/notifications`.
  3. Version 2.

## 5. Left to the builder
- Copy of the notice and the confirmation push.
- Link-code expiry and attempt limits.
- How approvals mirror between Apple's `knownHandles` and the server.
- Art for the padlocked bell and the Kittens panel, as `_ph` placeholders.
- Tests: Miniflare for link, consent, revoke and push gating, and Swift Testing for the kitten states.
