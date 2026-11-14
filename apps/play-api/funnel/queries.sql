-- The first-run funnel's saved queries. Run them with funnel/query.sh (docs/funnel.md).
--
-- Each query starts with a "-- name:" line. They look at devices minted in the last 30 days;
-- change '-30 days' (every query has it once) for another window. Times are epoch milliseconds.
-- A test runs every query here against sample data (src/funnel/queries.test.ts).

-- name: funnel
-- The main path, in order: how many devices reached each step, as a share of installs and of
-- the step before.
WITH cohort AS (
  SELECT id FROM devices
  WHERE created_at IS NOT NULL AND created_at >= unixepoch('now', '-30 days') * 1000
),
steps (n, milestone) AS (
  VALUES (1, 'device_created'), (2, 'age_done'), (3, 'named'), (4, 'home_seen'), (5, 'seat_taken'),
    (6, 'first_move'), (7, 'game_finished'), (8, 'game_with_human'), (9, 'game_with_device')
),
counts AS (
  SELECT s.n, s.milestone, COUNT(m.id) AS devices
  FROM steps s
  LEFT JOIN milestones m ON m.milestone = s.milestone AND m.id IN (SELECT id FROM cohort)
  GROUP BY s.n, s.milestone
)
SELECT n, milestone, devices,
  ROUND(100.0 * devices / NULLIF((SELECT COUNT(*) FROM cohort), 0), 1) AS pct_of_installs,
  ROUND(100.0 * devices / NULLIF(LAG(devices) OVER (ORDER BY n), 0), 1) AS pct_of_previous
FROM counts
ORDER BY n;

-- name: side_steps
-- Steps off the main path: making a table, inviting, being invited, notifications.
WITH cohort AS (
  SELECT id FROM devices
  WHERE created_at IS NOT NULL AND created_at >= unixepoch('now', '-30 days') * 1000
),
steps (n, milestone) AS (
  VALUES (1, 'table_created'), (2, 'invite_sent'), (3, 'link_opened'), (4, 'invite_pasted'), (5, 'joined_table'),
    (6, 'push_answered'), (7, 'push_allowed')
)
SELECT s.milestone, COUNT(m.id) AS devices,
  ROUND(100.0 * COUNT(m.id) / NULLIF((SELECT COUNT(*) FROM cohort), 0), 1) AS pct_of_installs
FROM steps s
LEFT JOIN milestones m ON m.milestone = s.milestone AND m.id IN (SELECT id FROM cohort)
GROUP BY s.n, s.milestone
ORDER BY s.n;

-- name: median_times
-- The median time between two steps, over the devices that reached both (in that order).
WITH cohort AS (
  SELECT id FROM devices
  WHERE created_at IS NOT NULL AND created_at >= unixepoch('now', '-30 days') * 1000
),
pairs (n, from_step, to_step) AS (
  VALUES (1, 'device_created', 'age_done'), (2, 'age_done', 'named'), (3, 'named', 'home_seen'),
    (4, 'device_created', 'seat_taken'), (5, 'device_created', 'first_move'),
    (6, 'device_created', 'game_finished'), (7, 'device_created', 'game_with_human'),
    (8, 'link_opened', 'joined_table'), (9, 'joined_table', 'first_move')
),
gaps AS (
  SELECT p.n, p.from_step, p.to_step, (b.at - a.at) / 1000.0 AS seconds
  FROM pairs p
  JOIN milestones a ON a.milestone = p.from_step
  JOIN milestones b ON b.id = a.id AND b.milestone = p.to_step AND b.at >= a.at
  WHERE a.id IN (SELECT id FROM cohort)
),
ranked AS (
  SELECT n, from_step, to_step, seconds,
    ROW_NUMBER() OVER (PARTITION BY n ORDER BY seconds) AS r,
    COUNT(*) OVER (PARTITION BY n) AS c
  FROM gaps
)
SELECT from_step, to_step, MAX(c) AS devices, ROUND(AVG(seconds), 1) AS median_seconds
FROM ranked
WHERE r IN ((c + 1) / 2, (c + 2) / 2)
GROUP BY n, from_step, to_step
ORDER BY n;

-- name: by_source
-- The main path by how a device first came: on its own, a table link, a request-to-play link,
-- a pasted invite ("unknown": the app hasn't said yet, or is older than 1.2).
WITH cohort AS (
  SELECT id, COALESCE(source, 'unknown') AS source FROM devices
  WHERE created_at IS NOT NULL AND created_at >= unixepoch('now', '-30 days') * 1000
),
reached AS (
  SELECT c.source, c.id,
    MAX(m.milestone = 'named') AS named,
    MAX(m.milestone = 'seat_taken') AS seated,
    MAX(m.milestone = 'first_move') AS moved,
    MAX(m.milestone = 'game_finished') AS finished,
    MAX(m.milestone = 'game_with_human') AS with_human
  FROM cohort c
  LEFT JOIN milestones m ON m.id = c.id
  GROUP BY c.source, c.id
)
SELECT source, COUNT(*) AS installs,
  SUM(named) AS named, SUM(seated) AS seated, SUM(moved) AS first_move,
  SUM(finished) AS game_finished, SUM(with_human) AS game_with_human,
  ROUND(100.0 * SUM(moved) / COUNT(*), 1) AS pct_first_move,
  ROUND(100.0 * SUM(with_human) / COUNT(*), 1) AS pct_with_human
FROM reached
GROUP BY source
ORDER BY installs DESC, source;

-- name: retention
-- Day 1 and day 7 return per weekly cohort (weeks start on Monday, UTC): the share of devices
-- that were in use on that day of their life. The latest weeks haven't had their day 7 yet.
WITH cohort AS (
  SELECT id, date(created_at / 1000, 'unixepoch', '-6 days', 'weekday 1') AS week FROM devices
  WHERE created_at IS NOT NULL AND created_at >= unixepoch('now', '-30 days') * 1000
),
returned AS (
  SELECT c.week, c.id,
    MAX(d.day = 1) AS day_1,
    MAX(d.day = 7) AS day_7,
    MAX(d.day BETWEEN 1 AND 7) AS any_1_to_7
  FROM cohort c
  LEFT JOIN device_days d ON d.id = c.id
  GROUP BY c.week, c.id
)
SELECT week, COUNT(*) AS installs,
  ROUND(100.0 * COALESCE(SUM(day_1), 0) / COUNT(*), 1) AS pct_day_1,
  ROUND(100.0 * COALESCE(SUM(day_7), 0) / COUNT(*), 1) AS pct_day_7,
  ROUND(100.0 * COALESCE(SUM(any_1_to_7), 0) / COUNT(*), 1) AS pct_any_1_to_7
FROM returned
GROUP BY week
ORDER BY week DESC;

-- name: by_game
-- Which game each device first played and finished in.
WITH cohort AS (
  SELECT id FROM devices
  WHERE created_at IS NOT NULL AND created_at >= unixepoch('now', '-30 days') * 1000
)
SELECT game,
  SUM(milestone = 'table_created') AS first_table,
  SUM(milestone = 'first_move') AS first_move,
  SUM(milestone = 'game_finished') AS first_finish,
  SUM(milestone = 'game_with_human') AS first_with_human
FROM milestones
WHERE game IS NOT NULL AND id IN (SELECT id FROM cohort)
GROUP BY game
ORDER BY first_move DESC, game;

-- name: invite_pages
-- Invite pages viewed on the web per day (UTC). Previews are Messages and other apps fetching
-- the link to draw its card, about one per invite sent; the rest are people opening it.
SELECT day,
  SUM(CASE WHEN page = 'j' THEN views ELSE 0 END) AS table_link_opened,
  SUM(CASE WHEN page = 'j_preview' THEN views ELSE 0 END) AS table_link_previews,
  SUM(CASE WHEN page = 'p' THEN views ELSE 0 END) AS play_link_opened,
  SUM(CASE WHEN page = 'p_preview' THEN views ELSE 0 END) AS play_link_previews
FROM page_views
WHERE day >= date('now', '-30 days')
GROUP BY day
ORDER BY day DESC;
