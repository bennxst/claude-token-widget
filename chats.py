# Zeigt pro Chat die aktuelle Kontextgröße und den Cache-Verbrauch.
# Start: python3 chats.py
import json, glob, os, datetime
LIMIT = 150_000  # ab dieser Kontextgröße lohnt sich ein neuer Chat
root = os.path.expanduser("~/.claude/projects")
rows = []
for f in glob.glob(root + "/**/*.jsonl", recursive=True):
    if "/subagents/" in f:
        continue
    seen, cache_read, last_ctx, title, msgs = set(), 0, 0, "", 0
    for line in open(f, errors="ignore"):
        try: d = json.loads(line)
        except Exception: continue
        m = d.get("message")
        if not isinstance(m, dict): continue
        if d.get("type") == "user" and not title:
            c = m.get("content")
            if isinstance(c, list):
                c = next((x.get("text", "") for x in c if isinstance(x, dict) and x.get("type") == "text"), "")
            if isinstance(c, str) and not c.startswith("<"):
                title = c.strip().replace("\n", " ")[:50]
        u = m.get("usage")
        if not u: continue
        key = (m.get("id"), d.get("requestId"))
        if key in seen: continue
        seen.add(key)
        msgs += 1
        cache_read += u.get("cache_read_input_tokens") or 0
        last_ctx = sum(u.get(k) or 0 for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
    if msgs:
        rows.append((cache_read, last_ctx, msgs, os.path.getmtime(f), title or os.path.basename(f)[:8]))
rows.sort(reverse=True)
print(f"{'Cache gelesen':>14} {'Kontext':>9} {'Nachr.':>6}  {'Zuletzt':<11} Chat")
for cr, ctx, n, mt, t in rows[:15]:
    flag = "NEU STARTEN" if ctx > LIMIT else ""
    print(f"{cr/1e6:>12.1f}M {ctx/1e3:>8.0f}k {n:>6}  {datetime.date.fromtimestamp(mt)}  {t:<50} {flag}")
