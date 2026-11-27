# App Review notes

The text between the two lines below is meant to be pasted into App Store Connect (App Review
Information, then Notes). It is about 3,500 of App Store Connect's 4,000 characters. Keep it in step
with the app: the birth year, the button names and the consent steps.

---

Pounce has five family games (Cat Tower, Tuna Tiles, Birdwatch, Toy Tumble, Purrtrait) and four daily puzzles. No account is needed, and there is no chat and no public profile.

AGE CHECK (first launch)
The app asks Apple's Declared Age Range. If you don't share, it asks "What year were you born?". Type 1980, tap the check, then "Yes" at "Born in 1980?". This sets the device to an adult. Tap the check to keep the suggested name and cat.
The answer stays in the Keychain after a reinstall. On a device set as under 18, Settings (the gear on Home) has "Check with Apple" under Account.

PLAY ALONE AGAINST THE HOUSE CAT BOT
Fastest: on Home, tap Practice (Cat Tower).
Or tap Play on Cat Tower, Tuna Tiles, Birdwatch or Toy Tumble. In the lobby, tap "Add a player", then "House Cat" (Birdwatch needs four seats), then Start. Bots play their own turns.
Birdwatch: Bid or Pass, name trump, tap a card to play it.
Toy Tumble (new in 1.4, everyone plays at once): drag to move a toy, tap to turn it, flick down to drop it. Tap a trick, then any box.

INVITES (optional)
"Add a player" offers Same room (a QR code), Far away (a link) and This phone (pass the phone). Before Pounce is installed, a link opens a web page that copies the invite for Pounce's Paste button.

SIGN IN WITH APPLE (optional)
Keeps streaks across phones. In Settings, or on Home after playing with someone. Adults and teens only. Settings also has the privacy policy and account deletion.

DAILY DISH
On Home, tap Play on Sniff, Nine Lives, Cat Nap or Box Fort. Our server checks every move and works out every score. The header opens today's board: only you and people you have a streak with.

APPLE TV
No age check or sign-in. On Home, select a game; the TV shows a code and a QR code. In any browser, open play.conleychaos.com/play, type 1980 and a name, tap "Join" and type the code. Tap "Add a player", "House Cat", then Start. Menu (Back) opens the TV's menu.

PURRTRAIT (new in 1.4, draw and guess, starts on a TV)
On the Apple TV, or at play.conleychaos.com/play/tv in a computer's browser, pick Purrtrait. The TV shows an 8-character code that changes every 30 seconds. In the iPhone app, tap Join on Home and type it. A second player joins the same way from play.conleychaos.com/play in another browser. Tap Start. The drawer's phone shows a word, and the TV shows the drawing as it is drawn. Guesses are said out loud; the drawer taps "Got it", then who said it.
A drawing goes only from the drawer's phone to that table's TV, through our server, which keeps it in memory until the turn ends. It is never saved or shared. No microphone. There are no House Cats in Purrtrait.

UNDER 13 AND PARENT CONSENT
If the year means under 13: the name comes from a list, no sign-in, no share links, no server push. Local turn reminders still work.
A parent can allow turn alerts on a child's device (two devices and a phone that gets texts):
1. Child's device: Settings shows a padlocked bell and a six-digit code.
2. Parent's device (1980, signed in with Apple): Settings, Family, "Kids' alerts", "Add a child", type the six digits.
3. "Next step", read the notice, enter a mobile number.
4. Type the code from the Twilio Verify text. Alerts are on.
5. A day or two later the parent's devices get a confirmation with "Revoke".
The parent can turn alerts off or remove the child from the same panel. The number is used only for consent and is deleted when consent ends. Consent isn't needed to play.

---

## For JD before submitting

- The consent steps need the Twilio Verify secrets on production. Without them, step 3 says "We can't text a code right now" and nothing is sent.
- App Store Connect's demo account fields can stay empty: no login is needed to play, and Sign in with Apple uses the reviewer's own Apple Account.
- If Practice, "Add a player" or the Start button get new words before release, update "Play alone".
- The Daily Dish shows only while the server's `DAILY` flag is on. Turn it on before submitting, or App Review won't see it.
- If the Home panel or its Play buttons get new words, update "Daily Dish".
- Toy Tumble and Purrtrait show only while the server's `GAMES` flag lists `tumble` and `purrtrait` (it does in `apps/play-api/wrangler.jsonc`).
- `PURRTRAIT_APPLINKS` stays off until 1.4 is live, so during review a Purrtrait TV's QR opens the web player, not the app. That is why PURRTRAIT says to tap Join in the app and type the code. Once it is on, the camera opens the app too.
