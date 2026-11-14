# Pounce information security program

Draft for JD Conley (Conley Chaos LLC) to review, 4 November 2026. Written to meet the written-security-program requirement of the amended COPPA Rule, 16 CFR § 312.8 (a designated coordinator, a written risk assessment, safeguards, oversight of service providers, and an annual review). This is not legal advice.

## Scope

The Pounce iOS app (`apps/play-ios`), its server `play-api` (`apps/play-api`, Cloudflare Workers and Durable Objects at `play.conleychaos.com`), the build and deploy pipeline (GitHub Actions), and the Apple and Cloudflare accounts that run them. The data covered is listed in `docs/privacy/retention-policy.md`.

## Coordinator

- **JD Conley**, owner of Conley Chaos LLC, coordinates this program: keeps it current, runs the yearly review, and handles incidents and requests.

## Risk assessment

Written each review. Current risks and how they are handled:

| Risk | Likelihood | Impact | Safeguard |
|---|---|---|---|
| A device token is stolen and used to act as that device | Low | Seats and tables of that device | HMAC tokens, Keychain storage with `ThisDeviceOnly`, TLS only in Release |
| A person id seen at a table is used to claim that person | Medium | A guest player taken over | Person key (32 random bytes, Keychain) proves the person; the server keeps only its SHA-256 and trusts the first key it sees |
| A replayed Sign in with Apple token | Low | Sign-in as someone else | RS256 check against Apple's keys, `aud`, `iss`, `exp`, and a single-use nonce |
| Secrets leak from the repo | Low | APNs or Apple key abuse | Secrets live only in GitHub Actions secrets and `wrangler secret`; `.dev.vars` is gitignored; gitleaks |
| Logs expose personal data | Low | Names or ids in Cloudflare logs | Invocation logs off; error logs carry codes only |
| A child's data is collected beyond internal operations | Medium | COPPA violation | Age screen before any profile upload; kitten limits in the app and on the server (no push, no sign-in, generated names only) |
| A deleted account comes back | Low | Data kept after deletion | Rooms ignore reports for players that don't exist; deletion revokes Apple tokens when the key is set |

## Safeguards

- **Minimization:** no email, no Apple name, no location, no contacts, no third-party analytics or SDKs. The first-run funnel (`docs/funnel.md`) keeps anonymous getting-started steps on our own server, keyed by a hash of the device id. Ages are kept as a band; birth years never leave the device.
- **Transport:** HTTPS only in Release builds (`https://play.conleychaos.com`); App Transport Security allows plain HTTP only for local networking in Debug.
- **Storage:** device credential, person keys and the age record in the Keychain, not synchronizable, readable after first unlock on this device only. Server data in SQLite-backed Durable Objects, encrypted at rest by Cloudflare.
- **Access:** only JD holds the Cloudflare, Apple Developer, App Store Connect and GitHub admin accounts, each with two-factor authentication. CI uses an App Store Connect API key and a Cloudflare API token scoped to this worker, both kept as GitHub environment secrets for `production`.
- **Code:** every change goes through a pull request with CI (type checks, lint, tests, the iOS build); the server's input parsers reject unknown keys and cap sizes.
- **Retention:** automatic expiry by Durable Object alarms (retention policy).

## Service providers

- **Cloudflare** (hosting, storage): processes data only to run the worker. Review its data processing addendum each year.
- **Apple** (App Store, TestFlight, APNs, Sign in with Apple, Declared Age Range): receives push payloads (names and table names) and sign-in requests.
- **GitHub** (source and CI): holds code and encrypted secrets, no user data.
- Before adding any provider that would receive user data, update this program and the privacy page first.

## Incidents

1. Contain: rotate the affected secret (`TOKEN_SECRET`, APNs or Sign in with Apple key, API keys); disable the route if needed.
2. Assess what data and which players were affected, from code and storage, not logs.
3. Notify affected people (and parents for any child) and the FTC or state authorities where the law requires, within the time the law sets.
4. Write up the cause and the fix in the repo's docs, and add a test.

## Review

- Every November, and after any incident or any PR that adds a new kind of data. Record the date and the changes here.
- **2026-11-04:** first draft (daily habit PR 2).
