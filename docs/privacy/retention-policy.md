# Pounce data retention policy

Draft for JD Conley (Conley Chaos LLC) to review, 4 November 2026. Written to meet the written-retention requirement of the amended COPPA Rule, 16 CFR § 312.10, and the retention rules in the daily habit design (`docs/superpowers/specs/2026-11-04-daily-habit-design.md` §14, §14.1). This is not legal advice. The public summary is the privacy page served by `apps/play-api/src/http/privacy.ts` at `play.conleychaos.com/privacy`; keep the two in step.

## Principles

- Keep data only as long as the game needs it to run. Nothing is kept for analytics, ads or resale, because Pounce collects none of those.
- Delete automatically wherever the server can (Durable Object alarms), so retention never depends on someone remembering.
- A child's data (age band `kitten`, under 13) gets no longer retention than anyone else's, and the same 90-day guest expiry applies.

## What is kept, why, and for how long

| Data | Where | Purpose | Kept for | How it is deleted |
|---|---|---|---|---|
| Device id and device token (HMAC) | App Keychain; `DeviceIndex` DO | Lets the device rejoin its tables | Until the app's data is deleted; the server record goes with its players | Server: removed with the player data it indexes. App: removed with the app. |
| Person id and person key hash | App (`people.json`, Keychain); `Identities` DO, `Player` DO | Binds a guest player to the device that holds the key | With the player | Player deletion or guest expiry removes the identity rows. |
| Name and cat | `Player` DO meta; seats in `GameRoom` | Shown to people at the same table | With the player; seats with the room | Account deletion; guest expiry; room close. |
| Age band (`kitten`, `teen`, `adult`) | `Player` and `DeviceIndex` | Age limits and safety defaults (§14.1) | With the player | With the player. The birth year typed on the age keypad is never stored: the app turns it into a band on the device and discards it at once (FTC policy statement, February 2026). |
| Time zone | `DeviceIndex` | The day boundary for streaks | While the device is in use | Replaced by every profile upload; removed with the device record. |
| APNs push token | `DeviceIndex` | "Your move" notifications | Until APNs reports it dead or the app uploads a new one | Forgotten on a 410 or `BadDeviceToken`. For a kitten, kept only with a parent's consent (PR 9), and deleted from all of the kitten's devices the moment consent ends. |
| Sign in with Apple subject hash | `Identities`, `Player` | Finds the player on sign-in | With the identity | Unlink, sign-out of the last device, or account deletion. |
| Sign in with Apple refresh token | `Player.identities.secret` (only when `PLAY_API_SIWA_KEY_P8` is set) | Revocation on deletion, as Apple requires | With the identity | Revoked with Apple, then deleted, on unlink and on account deletion. |
| Synced state: settings, tutorial flags, archive | `Player.state` | Same settings and tables on every device | With the player | Account deletion; guest expiry. |
| Household people listed on an account | `Player.household` | Pass-and-play people follow the owner to another device | While the device that listed them stays linked | Sign-out or detach of that device; account deletion. |
| Tables list | `Player`, `DeviceIndex` | Home's list of tables | Until the room closes | Room close removes the entry. |
| Streak day rows (PR 3) | `Pair` DO | The shared streak | 120 days | Settlement prunes older rows. Lifetime counters stay with the pair until a member leaves it or deletes their account. |
| Play-time histogram (PR 5) | `Player.playtime` | Learning reminder times | With the player | Never collected for a kitten; account deletion. |
| Pounces (PR 5) | `Player.pounces` | "Come play with me" | 7 days | Alarm deletes them. |
| Pounce links (PR 5) | `Links` DO | Messages invites | 24 hours, or once used | Deleted on use or expiry. |
| Parent's mobile number (PR 9) | `Consents` DO (per kitten), its HMAC in `KittenIndex`; Twilio's message logs for the two texts | Verifiable parental consent by text plus, and STOP replies | While consent lasts; 7 days if never confirmed (16 CFR 312.5(c)(1)) | Deleted on revocation (in the app, the revoke link, STOP, `RESCIND_CONSENT`), on the 7-day expiry, when the child turns 13 or is deleted, and when the consenting parent unlinks or deletes their account. Our texts are deleted from Twilio's logs at the same moment (by message SID); one Twilio can't delete yet is retried on the next change. JD: also set the Messaging Service's data retention to the shortest offered. |
| Consent record: linked parents, state, approved people (PR 9) | `Consents` DO | Which parents may manage a kitten, and who may reach it | While at least one parent stays linked and the kitten is under 13 | Deleted when the last parent unlinks, the kitten turns 13, or the kitten's player is deleted or expires. Revocation keeps parents and approvals (no contact information) so consent can be given again. |
| Link codes (PR 9) | `KittenIndex` | Linking a kitten's device to a parent | 10 minutes, or once used | Alarm and use delete them. Failed tries: 10 minutes. |
| Text link tokens (PR 9) | `KittenIndex` | The confirm and revoke links in the texts | Confirm: 7 days or once used. Revoke: while consent lasts | Deleted on use, expiry or revocation. |
| App transaction id (PR 9) | `Consents`, `KittenIndex` | Matching Apple's `RESCIND_CONSENT` to the kitten | With the consent record | Deleted with the record. |

## Expiry rules

- **Guest players:** a player with no sign-in identity that no device has touched for 90 days is deleted, together with its identities, device links and seats (seats fall back to the device). Implemented by `Player.alarm` (`GUEST_TTL_MS`).
- **Merged guest stubs:** 30 days after a merge (`STUB_TTL_MS`).
- **Accounts:** kept until the person deletes the account in the app, which runs `deleteMe` (§14). There is no inactivity expiry for signed-in accounts yet; decide one before the App Store launch.

## Logs

- Worker invocation logs are off (`wrangler.jsonc`). Error logs carry codes only: no player ids, pair ids, tokens, names or room codes.
- Cloudflare's own platform logs follow Cloudflare's retention; we keep no copy.

## Backups

- Durable Object storage has Cloudflare's point-in-time recovery (30 days). We take no other backups, so a deletion is final once that window passes.

## Requests

- A parent or player can ask to review or delete data by writing to privacy@conleychaos.com. Answer within 30 days. For a child, delete the player (or players) on that device by its person ids; no proof beyond the device is needed, because the app holds nothing that identifies the child.

## Review

- Reviewed with the security program each November, and whenever a PR adds a new kind of data. Next review: November 2027.

## Open items for JD

- Confirm that `privacy@conleychaos.com` exists and is read.
- COPPA's direct notice (§ 312.4(d)) asks for the operator's postal address and telephone number as well as an email. Add them to the privacy page before the App Store launch.
- Decide an inactivity expiry for signed-in accounts.
