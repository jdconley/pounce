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
| `apps/play-api` | The game server: a Cloudflare Worker with one Durable Object per room. It owns the rules, the bots and the hidden hands. |
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

## License

[MIT](LICENSE)
