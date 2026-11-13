"""Black-box RLS probe using only the public (anon) key.

Usage: python tools/rls_probe.py <SUPABASE_URL> <ANON_KEY>

For every table it tries to read, insert, update and delete as an anonymous caller.
PASS means the caller got nothing back / was refused. Anything else is printed as FAIL.
It never sends a service-role key and never needs a login.
"""
import json
import sys
import urllib.error
import urllib.request

url, anon = sys.argv[1].rstrip("/"), sys.argv[2]
H = {"apikey": anon, "Authorization": f"Bearer {anon}", "Content-Type": "application/json",
     "Prefer": "return=representation"}
TABLES = ["projects", "sessions", "events", "reports", "retests", "event_definitions", "ingest_log"]
ZERO = "00000000-0000-0000-0000-000000000000"
NOROW = {"events": "0"}   # events.id is a bigint; every other table uses a uuid


def call(method, path, body=None):
    req = urllib.request.Request(url + path, method=method, headers=H,
                                 data=None if body is None else json.dumps(body).encode())
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


COLS = {
    "projects": ["name"], "sessions": ["project_id", "build_version", "tester_id"],
    "events": ["project_id", "name"], "reports": ["project_id", "build_version", "tester_id", "description"],
    "retests": ["project_id", "build_version"], "event_definitions": ["project_id", "name"],
    "ingest_log": ["project_id"],
}
results = []


def check(name, ok, detail):
    if "PGRST205" in detail or "PGRST202" in detail:
        print("SKIP " + name + "  ->  not created yet (run migration 0004)")
        return
    results.append(ok)
    print(("PASS " if ok else "FAIL ") + name + "  ->  " + detail[:140])


for t in TABLES:
    s, b = call("GET", f"/rest/v1/{t}?select=*&limit=5")
    empty = s in (401, 403, 404) or (s == 200 and b.strip() == "[]")
    check(f"anon SELECT {t}", empty, f"HTTP {s} {b}")
    rid = NOROW.get(t, ZERO)
    idcol = "project_id" if t == "ingest_log" else "id"   # ingest_log has no id column
    # A well-formed row (valid columns) so a refusal can only come from RLS / grants, not from a bad request.
    row = {"project_id": ZERO, "name": "probe", "build_version": "x", "tester_id": "probe", "description": "probe"}
    s, b = call("POST", f"/rest/v1/{t}", {k: v for k, v in row.items() if k in COLS[t]})
    check(f"anon INSERT {t}", s in (401, 403, 404), f"HTTP {s} {b}")
    s, b = call("PATCH", f"/rest/v1/{t}?{idcol}=eq.{rid}", {"project_id": rid} if t == "ingest_log" else ({"id": rid} if t != "events" else {"name": "probe"}))
    check(f"anon UPDATE {t}", s in (401, 403, 404) or (s in (200, 204) and b.strip() in ("", "[]")), f"HTTP {s} {b}")
    s, b = call("DELETE", f"/rest/v1/{t}?{idcol}=eq.{rid}")
    check(f"anon DELETE {t}", s in (401, 403, 404) or (s in (200, 204) and b.strip() in ("", "[]")), f"HTTP {s} {b}")

for fn, args in [("delete_my_account", {}), ("regenerate_ingest_key", {"p_project": ZERO})]:
    s, b = call("POST", f"/rest/v1/rpc/{fn}", args)
    check(f"anon RPC {fn}", s in (401, 403, 404) or "not_signed_in" in b, f"HTTP {s} {b}")

# Ingest with a wrong key must be refused and must reveal nothing.
s, b = call("POST", "/rest/v1/rpc/sdk_ingest", {
    "p_ingest_key": ZERO, "p_build": "x", "p_tester": "probe", "p_client_session_id": "probe", "p_events": []})
check("sdk_ingest with an invalid key", s in (400, 401, 403, 404), f"HTTP {s} {b}")

print(f"\n{sum(results)}/{len(results)} checks passed")
sys.exit(0 if all(results) else 1)
