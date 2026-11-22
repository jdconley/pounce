#!/usr/bin/env python3
"""Daily Dish cross-platform check: each run in the proxy log, by who played it.

  python3 analyze.py <log.jsonl> <plan.json> [client ...]
  python3 analyze.py --tv <log.jsonl> <plan.json> [tv client ...]

For every run: the client, the date, the puzzle's hash, the moves the server accepted (in order,
resends counted once) and their hash, and the server's result. Compared with the plan.

With --tv: for each TV client (default appletv and web), every watch frame its board socket was
sent, per game: how many distinct frames, the hash of each frame's puzzle (against the plan), the
hash of the whole sequence of states, and the result in its watchEnd. The TVs pass when, game by
game, their puzzle hashes and state sequences are the same, every frame is one of the phone's run's
states in order, and the last frame is the run's final state.
"""
import hashlib, json, re, sys

def canon(v):
    if isinstance(v, list): return "[" + ",".join(canon(x) for x in v) + "]"
    if isinstance(v, dict): return "{" + ",".join(json.dumps(k) + ":" + canon(v[k]) for k in sorted(v)) + "}"
    return json.dumps(v, separators=(",", ":"), ensure_ascii=False)

h = lambda v: hashlib.sha256(canon(v).encode()).hexdigest()[:16]
if sys.argv[1] == "--tv":
    log, planfile, *tvs = sys.argv[2:]
    tvs = tvs or ["appletv", "web"]
    plans = {p["game"]: p for p in json.load(open(planfile))["plans"]}
    seen = {c: {} for c in tvs}
    for line in open(log):
        e = json.loads(line)
        if e.get("method") != "WSMSG" or e["client"] not in seen: continue
        m = e["msg"]
        if m.get("t") == "watch":
            frames = seen[e["client"]].setdefault(m["game"], {"puzzles": set(), "states": [], "end": None})
            frames["puzzles"].add(h(m["puzzle"]))
            st = h(m["state"])
            if not frames["states"] or frames["states"][-1] != st: frames["states"].append(st)  # a reconnect resends the latest
        elif m.get("t") == "board":
            board = {g["game"]: [(r["player"], r["rank"], {k: (r["result"] or {}).get(k) for k in ("outcome", "points", "guesses", "hints", "timeMs")}) for r in g["rows"]] for g in m["board"]["games"]}
            seen[e["client"]]["_board"] = (board, [(r["player"], r["points"], r["crowns"]) for r in m["board"]["dish"]["rows"]])
        elif m.get("t") == "watchEnd" and m.get("result"):
            seen[e["client"]].setdefault(m["game"], {"puzzles": set(), "states": [], "end": None})["end"] = {k: m["result"].get(k) for k in ("outcome", "points", "guesses", "hints")}
    for game in ["sniff", "nine-lives", "cat-nap", "box-fort"]:
        rows = {c: seen[c].get(game) for c in tvs}
        same = all(r is not None for r in rows.values()) and len({(tuple(sorted(r["puzzles"])), tuple(r["states"]), json.dumps(r["end"], sort_keys=True)) for r in rows.values()}) == 1
        phone = plans[game].get("states", [])
        for c, r in rows.items():
            if r is None:
                print(json.dumps({"game": game, "tv": c, "frames": 0, "pass": False})); continue
            # Every frame is one of the phone's run's states, in the order the moves made them.
            at = [phone.index(x) if x in phone else -1 for x in r["states"]]
            # ...ending on the run's final state: a TV's last picture is the board as it ended.
            inorder = bool(phone) and -1 not in at and at == sorted(at) and at[-1] == len(phone) - 1
            print(json.dumps({"game": game, "tv": c, "frames": len(r["states"]), "ofPhoneStates": f"{at[0] if at else '-'}..{at[-1] if at else '-'} of 0..{len(phone) - 1}",
                              "puzzleHash": sorted(r["puzzles"]), "planHash": plans[game]["puzzleHash"], "statesHash": h(r["states"]), "end": r["end"],
                              "pass": same and inorder and r["puzzles"] == {plans[game]["puzzleHash"]}}))
    boards = {c: seen[c].get("_board") for c in tvs}
    print(json.dumps({"board": {c: b for c, b in boards.items()}, "same": len({json.dumps(b, sort_keys=True) for b in boards.values()}) == 1}))
    sys.exit(0)

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
