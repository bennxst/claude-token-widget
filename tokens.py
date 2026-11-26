import json, glob, os, collections
root = os.path.expanduser("~/.claude/projects")
seen = set()
tot = collections.Counter()
by_model = collections.defaultdict(collections.Counter)
by_day = collections.defaultdict(collections.Counter)
files = glob.glob(root + "/**/*.jsonl", recursive=True)
for f in files:
    for line in open(f, errors="ignore"):
        try: d = json.loads(line)
        except Exception: continue
        m = d.get("message")
        if not isinstance(m, dict): continue
        u = m.get("usage")
        if not u: continue
        key = (m.get("id"), d.get("requestId"))
        if key in seen and key != (None, None): continue
        seen.add(key)
        for k in ("input_tokens","output_tokens","cache_creation_input_tokens","cache_read_input_tokens"):
            v = u.get(k) or 0
            tot[k] += v
            by_model[m.get("model","?")][k] += v
            by_day[(d.get("timestamp") or "?")[:10]][k] += v
total = sum(tot.values())
import sys
if "--json" in sys.argv:
    print(json.dumps({"total": total}))
    sys.exit()
print(f"\n  INSGESAMT: {total:,} Tokens".replace(",", ".") + f"  (= {total/1e9:.2f} Mrd.)\n")
print("Dateien:", len(files))
print("GESAMT:", dict(tot), "Summe:", sum(tot.values()))
for mo, c in by_model.items():
    print(mo, dict(c), "Summe:", sum(c.values()))
for day in sorted(by_day)[-7:]:
    print(day, sum(by_day[day].values()))
