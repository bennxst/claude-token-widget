# Hook (UserPromptSubmit): warnt, wenn der Chat zu groß geworden ist.
import json, sys, os
LIMIT = 150_000
try:
    p = json.load(sys.stdin).get("transcript_path")
    size = os.path.getsize(p)
    with open(p, "rb") as f:
        f.seek(max(0, size - 400_000))
        lines = f.read().decode("utf-8", "ignore").splitlines()
    ctx = 0
    for line in reversed(lines):
        try: u = json.loads(line).get("message", {}).get("usage")
        except Exception: continue
        if u:
            ctx = sum(u.get(k) or 0 for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
            break
    if ctx > LIMIT:
        print(json.dumps({"systemMessage": f"Token-Warnung: Dieser Chat ist {ctx//1000}k Tokens groß. Jede Nachricht liest alles erneut. Tippe /uebergabe und starte einen neuen Chat."}))
except Exception:
    pass
