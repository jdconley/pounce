# App Review notes

The text between the two lines below is meant to be pasted into App Store Connect (App Review
Information, then Notes). It is under App Store Connect's 4,000-character limit. Keep it in step
with the app: the birth year, the button names and the consent steps.

---

Pounce has two family card and tile games, Cat Tower and Tuna Tiles. No account is needed to play, and there is no chat and no public profile.

AGE CHECK (first launch)
The app first asks Apple's Declared Age Range. If you choose not to share, it asks "What year were you born?". Please type 1980, tap the check, then tap "Yes" when it says "Born in 1980?". This sets the device to an adult. Next, the app suggests a name and a cat; tap the check to keep them.
The answer is kept in the Keychain, so it stays after a reinstall. A wrong year can't be retyped. On a device set as under 18, Settings (the gear on Home), under Account, shows "Age not right?" and a "Check with Apple" button, which asks Declared Age Range again. Only Apple's answer changes the age.

PLAY ALONE AGAINST THE HOUSE CAT BOT
Fastest: on Home, tap Practice. A game against the House Cat bot starts right away.
Or:
1. On Home, tap Play on Cat Tower or Tuna Tiles.
2. In the lobby, a House Cat bot already holds a seat. To add more, tap "Add a player", then "House Cat".
3. Tap Start. The bot plays its own turns.
One device is enough. Turn reminders are local notifications from the device.

INVITES (optional, needs a second device)
In the lobby, "Add a player" offers Same room (a QR code to scan), Far away (a link to send) and This phone (pass the phone). A link opens the table in Pounce. If Pounce isn't installed, the link's web page copies the invite, and after installing, Pounce offers a Paste button (the system paste control) that opens the same table.

SIGN IN WITH APPLE (optional)
Signing in keeps your streaks if you change phones. Find it in Settings (the gear on Home), or on Home after you have played with someone. Adults and teens only. Settings also has the privacy policy and account deletion.

APPLE TV (no iPhone needed)
The Apple TV app has no age check and no sign-in. On Home, select Cat Tower or Tuna Tiles. The TV shows a table code and a QR code ("Scan to join"). On any browser, open play.conleychaos.com/play. A new browser asks the birth year (type 1980) and a name. Then tap "Join" and type the code (or scan the QR code). Tap "Add a player", then "House Cat", then Start. The TV shows the whole table; the browser holds the cards. Menu (Back) on the remote opens the TV's menu.

UNDER 13 ("kittens") AND PARENT CONSENT
If the year typed means under 13, the device is limited: the name comes from a list (dice), there is no sign-in, no share links, and no push notifications from the server. Local turn reminders still work, because nothing leaves the device.
A parent can allow turn alerts on a child's own device. This needs two devices and a phone that can receive a text:
1. Child's device (set up with a year under 13): Settings shows a padlocked bell and a six-digit code, with "Show this code to a grown-up".
2. Parent's device (an adult, signed in with Apple): Settings, then under Family, "Kids' alerts". Tap "Add a child" and type the six digits.
3. The parent taps "Next step", reads the notice (what we collect and how to turn it off), and enters a mobile number.
4. A text from Twilio Verify brings a six-digit code. The parent types it. Turn alerts are now on for that child.
5. A day or two later the parent's own devices get a confirmation notification with a "Revoke" button.
The parent can turn alerts off or remove the child at any time from the same panel. The phone number is used only for this consent and is deleted when consent ends.
In the lobby, a child's device without consent shows "Want turn alerts? Show a grown-up here your code." A signed-in parent at the same table with a linked child whose consent isn't finished is asked to set it up.

You don't need to test consent to play. If you would like to, use one device as the child (type a year under 13 on first launch) and one as the parent (type 1980, then sign in with Apple in Settings).

---

## For JD before submitting

- The consent steps need the Twilio Verify secrets on production. Without them, step 3 says "We can't text a code right now" and nothing is sent.
- App Store Connect's demo account fields can stay empty: no login is needed to play, and Sign in with Apple uses the reviewer's own Apple Account.
- If Practice, "Add a player" or the Start button get new words before release, update "Play alone".
