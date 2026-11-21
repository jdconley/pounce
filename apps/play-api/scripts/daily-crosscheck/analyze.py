#!/usr/bin/env python3
"""Daily Dish cross-platform check: each run in the proxy log, by who played it.

  python3 analyze.py <log.jsonl> <plan.json> [client ...]

For every run: the client, the date, the puzzle's hash, the moves the server accepted (in order,
resends counted once) and their hash, and the server's result. Compared with the plan.
"""
import hashlib, json, re, sys

def canon(v):
    if isinstance(v, list): return "[" + ",".join(canon(x) for x in v) + "]"
    if isinstance(v, dict): return "{" + ",".join(json.dumps(k) + ":" + canon(v[k]) for k in sorted(v)) + "}"
    return json.dumps(v, separators=(",", ":"), ensure_ascii=False)

h = lambda v: hashlib.sha256(canon(v).encode()).hexdigest()[:16]
log, planfile, *only = sys.argv[1:]
plans = {p["game"]: p for p in json.load(open(planfile))["plans"]}
runs = {}
for line in open(log):
    e = json.loads(line)
    if only and e["client"] not in only: continue
    m = re.match(r"/v1/daily/([a-z-]+)/start", e["url"])
    if m and e["status"] == 200:
        r = e["res"]
        runs.setdefault(r["run"], {"client": e["client"], "game": r["game"], "date": r["date"], "puzzle": h(r["puzzle"]), "moves": [], "reveals": [], "seen": set(), "result": r["result"], "first": e["at"]})
        continue
    m = re.match(r"/v1/daily/runs/([^/?]+)/moves", e["url"])
    if m and m.group(1) in runs and isinstance(e["res"], dict) and e["res"].get("ok"):
        run = runs[m.group(1)]
        frm = e["req"]["from"]
        if frm in run["seen"]: continue  # a resend: the same answer, counted once
        run["seen"].add(frm)
        run["moves"] += e["req"]["moves"]
        run["reveals"] += e["res"].get("reveals", [])
        if e["res"].get("result"): run["result"] = e["res"]["result"]

rows = []
for rid, r in sorted(runs.items(), key=lambda kv: kv[1]["first"]):
    if not r["result"]: continue
    p = plans.get(r["game"])
    res = r["result"]
    keep = {k: res[k] for k in ("outcome", "points", "guesses", "hints", "progress", "tooFast") if k in res}
    exp = p["expect"]
    ok = r["puzzle"] == p["puzzleHash"] and h(r["moves"]) == p["movesHash"] and all(res.get(k) == v for k, v in exp.items())
    rows.append({"client": r["client"], "game": r["game"], "date": r["date"], "puzzleHash": r["puzzle"], "moves": len(r["moves"]),
                 "movesHash": h(r["moves"]), "revealsHash": h(r["reveals"]), "result": keep, "timeMs": res["timeMs"], "pass": ok})
for row in rows: print(json.dumps(row))
