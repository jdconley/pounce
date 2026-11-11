# Pounce

Little games for couples, families and friends. Everyone can be on one phone,
on their own phone in the same room, or across the world, all in the same game.

The first game is **Cat Tower**: a set-collecting rummy game where cats climb a
ten-shelf cat tower, one phase per shelf. Yarn is wild, and a Cucumber makes
the next cat skip a turn.

"Pounce" is a code name.

## Layout

| Path | What it is |
| --- | --- |
| `apps/play-api` | The game server: a Cloudflare Worker with one Durable Object per room. It owns the rules, the bots and the hidden hands. It also serves the website (below). |
| `apps/play-ios` | The iOS app (SwiftUI shell, SpriteKit table). See its [README](apps/play-ios/README.md). |
| `docs/superpowers` | The design spec, implementation plans and follow-up notes. |

## Develop

Requires Node 24 and pnpm 10.

```bash
pnpm install
pnpm check   # lint, typecheck and tests
```

`apps/play-api` tests include a 300-game bot simulation and Miniflare
integration tests for the Worker and Durable Objects.

## Local dev server

Run the game server on your machine (the iOS Debug build talks to it at
`http://localhost:8787`):

```bash
cp apps/play-api/.dev.vars.example apps/play-api/.dev.vars   # gitignored
# fill TOKEN_SECRET with the output of: openssl rand -hex 32
pnpm --filter @pounce/play-api exec wrangler dev --port 8787
```

## The website

The same Worker serves the public site at `play.conleychaos.com`: the landing page (`/`), help
(`/support`), the privacy policy (`/privacy`) and the invite pages. They are plain HTML built in
`apps/play-api/src/http`, with no scripts and nothing loaded from another host.

How the landing page offers the app follows two settings, with no code change:

| Setting | Where | Effect |
| --- | --- | --- |
| `APP_STORE_URL` | `vars` in `apps/play-api/wrangler.jsonc`, empty today | Set to `https://apps.apple.com/app/id<number>` once the app is on the App Store: the page shows Apple's "Download on the App Store" badge, Safari's Smart App Banner, and a QR code on desktop. |
| `TESTFLIGHT_URL` | the same `vars`, set to the public beta link | Used only while `APP_STORE_URL` is empty (today): the page shows "Join the beta on TestFlight" and the QR code. |
| neither | | The page says "Coming soon to the App Store" and has no install button. |

`/get` redirects to whichever link is set (or home), so other sites and the QR code can point at
`https://play.conleychaos.com/get`.

The page's images and gameplay clip are built from the app icon, the cat art and the App Store
screenshots and preview under `apps/play-ios`, and committed in `apps/play-api/public`. After any
of those change, rebuild them (needs `ffmpeg`, `cwebp` and ImageMagick):

```bash
node apps/play-api/scripts/build-site-media.mjs
```

## Deploy

Every push to `main` that passes CI deploys `apps/play-api` to
`play.conleychaos.com`. The deploy skips itself until these GitHub Actions
secrets exist:

| Secret | Required | What it is |
| --- | --- | --- |
| `CLOUDFLARE_API_TOKEN` | yes | Token that can edit Workers and the `conleychaos.com` zone's routes. |
| `CLOUDFLARE_ACCOUNT_ID` | yes | The Cloudflare account that holds `conleychaos.com`. |
| `PLAY_API_TOKEN_SECRET` | yes | Signs device tokens. Generate with `openssl rand -hex 32`. Without it the API answers 503 and the smoke check fails. |
| `PLAY_API_APNS_KEY_P8` | no | APNs auth key (.p8 contents) for "your turn" pushes. Set it together with the key ID. |
| `PLAY_API_APNS_KEY_ID` | no | The APNs key's ID. |
| `PLAY_API_SIWA_KEY_P8` | no, until App Store submission | Sign in with Apple key (.p8 contents). Sign-in works without it, but the API keeps no Apple tokens, so it can't revoke them on account deletion as App Review requires. One key with both APNs and Sign in with Apple enabled can serve both pairs. Set it together with the key ID. |
| `PLAY_API_SIWA_KEY_ID` | no | The Sign in with Apple key's ID. |
| `PLAY_API_TWILIO_ACCOUNT_SID` | no | Twilio account SID (`AC…`), for parent consent (daily habit PR 9). Set all four Twilio secrets or none: without them no code is sent and a kitten's consent can't start. |
| `PLAY_API_TWILIO_API_KEY_SID` | no | A Twilio API key's SID (`SK…`): signs in to Verify (basic auth). |
| `PLAY_API_TWILIO_API_KEY_SECRET` | no | That API key's secret. |
| `PLAY_API_TWILIO_VERIFY_SERVICE_SID` | no | The Verify Service (`VA…`) that texts the parent a six-digit code. |

Parent consent uses **Twilio Verify**: Twilio texts the parent a code from its own pre-registered
senders, so Pounce needs no phone number of its own, no Messaging Service, no webhook and no A2P
10DLC or toll-free verification. Setup, all in the Twilio console:

1. **Verify, then Services, then Create new.** Friendly name `Pounce` (Verify's text reads "Your
   Pounce verification code is: …"), code length **6**, channel **SMS** on. Copy the Service SID
   (`VA…`).
2. Geo permissions for Verify (in the Service's settings, or Messaging's SMS geographic
   permissions): allow the **United States and Canada** only. The API sends codes only to +1
   numbers.
3. **Account, then API keys and tokens, then Create API key.** Friendly name `Pounce play-api`,
   type **Standard**. Copy its SID (`SK…`) and secret now; the secret isn't shown again.
4. Your account SID (`AC…`) is on the console's home page.
5. In GitHub, add the four secrets above (Settings, then Secrets and variables, then Actions). The
   next deploy syncs them; a partial set is skipped with a warning.

## License
## License

[MIT](LICENSE)
