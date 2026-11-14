# First-run funnel data

Where new players get stuck, from our own server (first-run funnel design, Part 3:
`docs/superpowers/specs/2026-11-13-first-run-funnel-design.md`). No analytics SDK, nothing sent
to any other company.

## What is kept

A Cloudflare D1 database, `conleychaos-play-funnel`, bound to the play API as `FUNNEL`. The Worker
creates its tables the first time it needs them; there is no migration to run.

| Table | One row per | Columns |
|---|---|---|
| `devices` | device | `id` (a keyed hash of the device id, never the id itself), `created_at` (when `POST /v1/devices` minted it; null for a device minted before tracking began), `first_seen`, `last_seen`, `platform`, `app_version`, `locale` ("en-US"), `source` |
| `milestones` | device and step | `id`, `milestone`, `at` (the first time), `game` (for table steps), `app_version` |
| `device_days` | device and day of its life it was used | `id`, `day` (0 is the day it was minted, up to 90) |
| `page_views` | UTC day and invite page | `day`, `page` (`j`, `p`, `j_preview`, `p_preview`), `views` |

Times are epoch milliseconds: `datetime(at / 1000, 'unixepoch')` reads one.

### Steps

The server records these itself:

| Step | When |
|---|---|
| `device_created` | The app's first launch minted a device (`POST /v1/devices`). |
| `table_created` | The device made a table. |
| `seat_taken` | The device holds a person's seat at a table, its own or anyone's. |
| `joined_table` | The device holds a seat at a table another device made. |
| `first_move` | The room accepted the device's first move. |
| `game_finished` | A game the device had a seat in ended. |
| `game_with_human` | A finished game with two or more people seated (pass and play counts). |
| `game_with_device` | A finished game with someone seated from another device. |

The app reports these (`POST /v1/funnel`, only after the age check; app 1.2 and later):

| Step | When |
|---|---|
| `age_done` | The age check finished. |
| `named` | The owner picked a name and cat. |
| `home_seen` | Home showed. |
| `invite_sent` | An invite to a table went out: the share sheet sent it, or its QR code showed. |
| `link_opened` | The app opened an invite, tapped or pasted. |
| `invite_pasted` | The app opened an invite from the clipboard. |
| `push_answered` | The notifications prompt was answered. |
| `push_allowed` | It was answered yes. |

`source` is how the device first came, as the app saw it until it first opened a table:
`organic`, `join_link` (a `/j` table link), `pounce_link` (a `/p` request to play) or `paste`.

Day 1 and day 7 return come from `device_days`: a device is counted as in use when it opens a
table, Home's table list, or reports a step (at most once an hour). Invite page views are counted
per day with nothing about the viewer; a link preview (Messages drawing the link's card) counts as
`*_preview`, about one per invite sent through Messages.

Only devices with a `created_at` are in the saved queries: devices minted before this shipped
have none, so the funnel starts clean.

Kept for a year after a device was last used; invite page counts for a year. Deleting your data
in the app deletes the device's rows. See `docs/privacy/retention-policy.md`.

## Running the saved queries

The queries are in `apps/play-api/funnel/queries.sql`, each under a `-- name:` line. They look at
devices minted in the last 30 days (change `'-30 days'` for another window).

| Name | What it answers |
|---|---|
| `funnel` | The main path, step by step: devices, share of installs, share of the step before. |
| `side_steps` | Tables made, invites sent and opened, joins, notifications. |
| `median_times` | Median seconds between two steps (install to first move, link to joined, ...). |
| `by_source` | The main path by how devices came. |
| `retention` | Day 1, day 7 and any return in days 1 to 7, per weekly cohort. |
| `by_game` | Which game devices first played and finished. |
| `invite_pages` | Invite pages opened per day, and link previews. |

From `apps/play-api`, with Wrangler signed in to the Conley Chaos Cloudflare account
(`pnpm exec wrangler login` once). `funnel/query.sh` runs saved queries by name (none: all of
them) and prints each as a table:

```bash
funnel/query.sh funnel by_source retention
```

Ad hoc questions go straight to Wrangler (add `--json` for JSON):

```bash
pnpm exec wrangler d1 execute conleychaos-play-funnel --remote --command "SELECT milestone, COUNT(*) AS devices FROM milestones GROUP BY milestone ORDER BY devices DESC"
```

`--file` runs SQL too, but against the remote database it prints only a summary, not rows. The
Cloudflare dashboard (Storage and databases, D1, `conleychaos-play-funnel`, Console) runs the same
SQL in a browser.

### Locally

`apps/play-ios/scripts/dev-server.sh` keeps a local copy of the database in
`apps/play-api/.wrangler/state`. After a simulator run against it:

```bash
funnel/query.sh --local
```

## Changing it

- A new step: add it to `src/funnel/milestones.ts` (server or app list), to `FunnelMilestone` in
  `apps/play-ios/PounceKit/Sources/PounceKit/Funnel/Funnel.swift` for an app step (a test holds the
  two lists together), and to a query in `funnel/queries.sql` (a test checks every step is named).
- Nothing personal: no names, no free text, no player or account ids, no table codes, no
  addresses. Update the privacy page (`src/http/privacy.ts`) and `docs/privacy/app-store-label.md`
  if what is kept changes.
