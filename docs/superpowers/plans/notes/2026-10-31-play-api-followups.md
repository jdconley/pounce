# play-api follow-ups (from Plan 1 reviews)

Deferred minor findings from per-task and whole-branch review of `apps/play-api`. None block merge.

## Client contract for Plan 2 (iOS)
- Apply every `snapshot` unconditionally, even when its `seq` equals the last event's seq (round-start snapshots share the last event's seq).
- Treat `room_closed` as terminal; the socket may not be closed by the server.
- `hands` in views serialize with string keys ("0").
- Upload the APNs token on every launch.
- Snapshots carry `protocol: 1`.

## Deferred findings
- Task 1: minor (deferred): rng.test.ts:214 lexicographic sort; duplicate describe("shuffle"); per-glob 100% gate unverified (check before final); .context/repos/shared-modules hand-copied into worktree for pnpm install
- Task 2: minor (deferred): canHit throws on unknown id (callers must check hand first); set/coat groups alias input array; fixtures assert validity only (no placement/canHit vectors — consider extending for iOS in Plan 2); YARN+1 magic in phases.test; matchPhase dedupe not sole guard
- Task 3: minor (deferred): engine trusts action shape (unknown type falls to discard; from!=discard → deck) — Ruling I: Task 8 parseClientMessage must fully validate Action shape (type, from enum, ints) — cost if wrong: malformed actions reach engine; termination comment wrong (engine.ts:184); stray cardPoints assertion test:845
- Task 4: minor (deferred): hit target.group non-number at runtime → covered by Ruling I (Task 8 validates ints); bad_card before bad_target ordering
- Task 5: minor (deferred): misleading test comment rounds.test L133 and vague title L170; implementer wrote impl before tests then reverted for RED (TDD order deviation, evidence real)
- Task 6: minor (deferred, recommend fixing before merge): leak test scoped to .hands only — add exact key-set assertion on CatTowerView + collision-free whole-view JSON leak check (deck/seed/discard contents)
- Task 7: minor (deferred): document/assert run+coat-last invariant in PHASES (solver.ts:32-40, phaseProgress 138-158); phaseProgress counts all-yarn groups (heuristic only); widen cross-check pool to 1..12; add per-game step cap in sim to surface Ruling-K stalemates (recommend before merge); property test mostly duplicates sim; long doc line house-cat.ts:22
- Task 8: minor (deferred): token base64 padding-bit malleability (canonical re-encode check); lowercase Person.id; name length in UTF-16 units / control chars; add __proto__ key tests; use Object.hasOwn; -0 seat
- Task 9: minor (deferred, recommend before merge): hand-isolation test asserts only inequality — assert exact hands keys per device incl. start broadcast; renumber cast `as Seat` should drop orphan codes; handle() has no rollback on throw (moveSeat drops old code before newMoveCode); dispatch lacks default → bad_message; moveSeat allowed when over; moveFailures never pruned; noisy compaction test setup
- Task 10: minor (deferred, recommend before merge): cleanup leaves botAt/nextRoundAt armed and tick doesn't early-return when over (re-sends room_closed if storage not deleted); asleep device flips back to away on disconnect/background; no push if device backgrounds after its turn began (product note); stray blank import line; TDD order deviation
- Task 11: minor (deferred, recommend before merge): close() keeps core set across removeTable await (late fetch accepted into dying room) — set closing flag first; tables RPC ordering (removeTable no timestamp guard, >= same-ms); readObject buffers before size check (use content-length); limiter prune O(n) when >10k IPs; no guard around core.handle+after; test brittleness (300ms sleep, miniflare disk layout, emitWarning patch); untested 503/bot_stalled/push/missing-header; alarm-close of never-sent sockets unverified in prod (clients must treat room_closed as terminal)
- Task 11: minor (deferred): hibernation tests rely on ~10s workerd eviction (11s sleep); no close()-after-wake test
- Task 12: minor (deferred): English "Not found" plain 404 body (use JSON notFound); svg role=img + aria-hidden conflict; ROOM_CODE placement in codes.ts; code escaping unreachable (regex gate)
- Task 13: minor (deferred, recommend before merge): unregistered-token delete races re-registration (DELETE ... AND v=sent token); JWT/key failures logged as network_error (add apns_key_invalid); cache keyed by kid only; DeviceIndex delete branch untested; APNS_HOST is production (correct for TestFlight; Xcode dev builds need sandbox)
- Task 14: minor (deferred): fail-fast smoke/deploy-parallel matrix — missing PLAY_API_TOKEN_SECRET or wrong zone on first merge can cancel sibling legs (JD must set secret before merge; optional follow-up fail-fast:false)
- Final wave: legacy numeric seed gives misleading RangeError (add length guard); plan doc still mentions mulberry32 / error.ref.
