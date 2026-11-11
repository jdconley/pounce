# Pounce: App Store Connect privacy and age rating answers

Draft for JD Conley (Conley Chaos LLC) to review, 10 November 2026. This is not legal advice and needs legal review before submission. It is a checklist for entering the App Privacy "nutrition label" and the age rating questionnaire by hand in App Store Connect. Every answer comes from what the code does today (app `apps/play-ios`, server `apps/play-api`). It must agree with the app's privacy manifest (`apps/play-ios/Pounce/Resources/PrivacyInfo.xcprivacy`), the public policy (`apps/play-api/src/http/privacy.ts`, served at `https://play.conleychaos.com/privacy`) and `docs/privacy/retention-policy.md`. A test (`apps/play-api/src/http/privacy-label.test.ts`) checks that the manifest and this file list the same data types. Change all four together when a feature adds data.

## Before you start

- **Privacy Policy URL** (App Information): `https://play.conleychaos.com/privacy`
- **User Privacy Choices URL**: leave empty. Deletion is in the app (gear, then the trash can or Delete my data).
- App Store Connect path: your app, then **App Privacy**, then **Get Started** (or **Edit**).

## App Privacy

### Question 1: "Do you or your third-party partners collect data from this app?"

**Yes, we collect data from this app.**

### Question 2: data types

Tick exactly these 9 boxes and nothing else.

| Category | Data type | Tick | What it is in Pounce |
|---|---|---|---|
| Contact Info | Name | Yes | The player name and cat each person picks. A child's name comes from a list of generated cat names. |
| Contact Info | Email Address | No | Sign in with Apple asks for no email. |
| Contact Info | **Phone Number** | **Yes** | Only a parent's mobile number, typed by a parent to consent for a child. Twilio Verify texts it a code. |
| Contact Info | Physical Address, Other Contact Info | No | |
| Health and Fitness | (all) | No | |
| Financial Info | (all) | No | |
| Location | Precise Location, Coarse Location | No | Only the device's time zone name (for example America/Los_Angeles) is sent. That is broader than Apple's coarse location; it is declared under Other Data. |
| Sensitive Info | Sensitive Info | No | |
| Contacts | Contacts | No | Invites use the share sheet or a QR code. |
| User Content | Emails or Text Messages | No | There is no chat. Nudges and requests to play are fixed messages. |
| User Content | Photos or Videos, Audio Data | No | |
| User Content | **Gameplay Content** | **Yes** | Seats, turns, game state, tables, streak days, rewards. |
| User Content | Customer Support | No | Support is by email, outside the app. |
| User Content | **Other User Content** | **Yes** | Table names that players type. |
| Browsing History | Browsing History | No | |
| Search History | Search History | No | |
| Identifiers | **User ID** | **Yes** | The server's player id, and a one-way hash of the Sign in with Apple id. |
| Identifiers | **Device ID** | **Yes** | The server-made device id, plus the push tokens for notifications, the widget and Live Activities. Not the IDFA or IDFV. |
| Purchases | Purchase History | No | Pounce sells nothing. |
| Usage Data | **Product Interaction** | **Yes** | Which tips were seen, archived tables, settings, and for players 13 and over a count of the times of day they play (for reminder timing). |
| Usage Data | Advertising Data | No | |
| Usage Data | **Other Usage Data** | **Yes** | Requests to play, invite links and their answers, nudges. |
| Diagnostics | Crash Data, Performance Data, Other Diagnostic Data | No | No crash or analytics SDK. Server error logs carry no device data. |
| Surroundings, Body | (all) | No | |
| Other Data | **Other Data Types** | **Yes** | The age band (under 13, 13 to 17, 18 and over; never a birth date), the time zone, the App Store app transaction id of a child's copy (to honor a parent withdrawing consent through Apple), and which people a parent approved. |

### Question 3: for each ticked type

Give the same three answers for all 9 types.

| Data type | Purposes (tick only these) | Linked to the user's identity? | Used for tracking? |
|---|---|---|---|
| Name | App Functionality | Yes | No |
| Phone Number | App Functionality | Yes | No |
| Gameplay Content | App Functionality | Yes | No |
| Other User Content | App Functionality | Yes | No |
| User ID | App Functionality | Yes | No |
| Device ID | App Functionality | Yes | No |
| Product Interaction | App Functionality | Yes | No |
| Other Usage Data | App Functionality | Yes | No |
| Other Data Types | App Functionality | Yes | No |

- Do **not** tick Third-Party Advertising, Developer's Advertising or Marketing, Analytics, Product Personalization or Other Purposes for any type.
- "Linked" is Yes because the server keys everything to a player id, even for guests who never sign in.
- Tracking is No. There is no ad SDK, no IDFA, no data broker and no sharing with other companies' apps.
- The parent's phone number may qualify for Apple's "optional disclosure" exception, but it is not infrequent for a parent. Declare it.

### Result to check on the product page preview

- **Data Used to Track You:** none.
- **Data Linked to You:** Contact Info, User Content, Identifiers, Usage Data, Other Data.
- **Data Not Linked to You:** none.

## App Tracking Transparency

The app shows no tracking prompt and needs none. `NSPrivacyTracking` is false in the manifest, with no tracking domains.

## Age rating questionnaire

Path: App Information, then **Age Rating**, then **Edit**. This uses Apple's 2025 questionnaire (ratings 4+, 9+, 13+, 16+, 18+). Wording on the form may differ slightly; answer by meaning.

### Features and capabilities

| Question | Answer | Why, from the code |
|---|---|---|
| Parental Controls | **Yes** | A parent's consent controls notifications on a child's device and who may ask the child to play (Kittens panel). It mirrors Screen Time Communication Limits. |
| Age Assurance | **Yes** | It asks every new player's age in a neutral way, using Declared Age Range (`requestAgeRange`) where it can, and applies age limits per band. |
| Unrestricted Web Access | **No** | One in-app web view shows only Pounce's own notice-to-parents page. Links open our own pages or Mail. |
| User-Generated Content | **Yes** | Players type their own names and table names, and other players at the table see them. There is no chat and no free text beyond names. |
| Messaging and Chat | **No** | Nudges and requests to play are fixed messages with no typed text. |
| Advertising | **No** | |

### Mature themes and content (all "None" / "No")

| Question | Answer |
|---|---|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Prolonged Graphic or Sadistic Realistic Violence | None |
| Profanity or Crude Humor | None |
| Mature or Suggestive Themes | None |
| Horror or Fear Themes | None |
| Sexual Content or Nudity | None |
| Graphic Sexual Content and Nudity | None |
| Alcohol, Tobacco, or Drug Use or References | None |
| Medical or Treatment Information | None |
| Health or Wellness Topics | No |
| Simulated Gambling | None (Cat Tower is a card game with no wagers, chips, coins or prizes) |
| Gambling (real money) | No |
| Contests | No |
| Loot Boxes | No |

### Other settings

- **Made for Kids:** **No.** The policy says Pounce is made for adults playing with their families, not for children on their own. Choosing Made for Kids would bring the Kids Category rules.
- **Age rating override:** none.
- **Expected result:** App Store Connect computes the rating. With no mature content it should come out at 4+ or 9+. User-generated content may raise it, depending on Apple's current rules. Record the computed rating here once entered.

## Needs JD

- **Legal review** of this file, the policy page and the notice to parents before submission.
- **App Store id.** Once App Store Connect shows the app's Apple ID (App Information, General Information, a number), set `APP_STORE_URL` in `apps/play-api/wrangler.jsonc` to `https://apps.apple.com/app/id<that number>`. That turns on the invite pages' Smart App Banner and the "Get the app" link.
- **Postal address and phone number** for the COPPA direct notice (see `retention-policy.md`, open items).
- Confirm `privacy@conleychaos.com` is read.
