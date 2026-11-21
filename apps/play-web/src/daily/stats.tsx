/**
 * One game's stats (spec §7 "Stats"): played, solve rate, the game's own streak and best, the best
 * time or points, and a small chart: Sniff's guesses 1 to 6, or the last 30 days of times or
 * points, gaps drawn empty.
 */
import { Button, Sheet } from "../ui/common";

import { clock } from "./format";
import { lookOf } from "./treats";

import type { Stats } from "@pounce/play-api/daily/board";
import type { DailyGameId } from "@pounce/play-api/daily/module";

const DAY_MS = 86_400_000;

/** The 30 dates ending on `today` (YYYY-MM-DD), oldest first. */
export function last30Dates(today: string): string[] {
  const end = Date.parse(`${today}T12:00:00Z`);
  return Array.from({ length: 30 }, (_, i) => new Date(end - (29 - i) * DAY_MS).toISOString().slice(0, 10));
}

function Figure(props: { value: string; label: string }) {
  return (
    <div class="dd-fig">
      <strong class="outlined">{props.value}</strong>
      <span>{props.label}</span>
    </div>
  );
}

export function StatsSheet(props: { game: DailyGameId; stats: Stats | null; today: string; onClose: () => void }) {
  const look = lookOf(props.game);
  const s = props.stats;
  const points = props.game === "box-fort";
  const sniff = props.game === "sniff";
  const byDate = new Map((s?.last30 ?? []).map((d) => [d.date, d.result]));
  const days = last30Dates(props.today).map((date) => ({ date, result: byDate.get(date) ?? null }));
  const values = days.map((d) => (d.result ? (points ? (d.result.points ?? 0) : d.result.timeMs) : 0));
  const top = Math.max(1, ...values);
  const most = Math.max(1, ...(s?.guesses ?? []));
  return (
    <Sheet title={`${look.title} stats`} onClose={props.onClose}>
      <div class="dd-stats" style={{ "--c": look.color, "--d": look.deep }}>
        <div class="dd-figs">
          <Figure value={String(s?.played ?? 0)} label="Played" />
          {points ? null : <Figure value={`${s && s.played > 0 ? Math.round((s.solved / s.played) * 100) : 0}%`} label="Solved" />}
          <Figure value={String(s?.streak ?? 0)} label="Streak" />
          <Figure value={String(s?.best ?? 0)} label="Best streak" />
        </div>
        <p class="dd-best-line">
          {points ? `Best: ${(s?.bestPoints ?? 0).toLocaleString("en-US")} points` : s?.bestTimeMs ? `Best: ${clock(s.bestTimeMs)}` : "Best: none yet"}
        </p>
        {sniff ? (
          <ol class="dd-guesses" aria-label="Solved in">
            {(s?.guesses ?? [0, 0, 0, 0, 0, 0]).map((n, i) => (
              <li key={i}>
                <span>{i + 1}</span>
                <i style={{ transform: `scaleX(${Math.max(0.06, n / most)})` }} />
                <b>{n}</b>
              </li>
            ))}
          </ol>
        ) : (
          <div class="dd-chart" role="img" aria-label={`Last 30 days: ${days.filter((d) => d.result).length} played`}>
            {days.map((d, i) => (
              <i
                key={d.date}
                class={d.result ? (d.result.outcome === "solved" || d.result.outcome === "done" ? "won" : "tried") : ""}
                style={{ transform: `scaleY(${d.result ? Math.max(0.12, (values[i] as number) / top) : 0.06})` }}
              />
            ))}
          </div>
        )}
        <p class="fine">{sniff ? "Guesses to solve" : points ? "Points, last 30 days" : "Times, last 30 days"}</p>
        <Button wide variant="violet" onClick={props.onClose}>
          Done
        </Button>
      </div>
    </Sheet>
  );
}
