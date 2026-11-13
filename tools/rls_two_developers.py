"""Cross-developer isolation test. Needs TWO real developer accounts (A and B).

Usage:
  python tools/rls_two_developers.py <URL> <ANON_KEY> <emailA> <passwordA> <emailB> <passwordB>

Signs in as A and B through the normal password endpoint, then checks that B cannot read or
modify anything A owns. Creates nothing and deletes nothing: the only write it tries is
an UPDATE/DELETE on A's rows as B, which must affect zero rows.
"""
import json
import sys
import urllib.request

url, anon, ea, pa, eb, pb = sys.argv[1].rstrip("/"), *sys.argv[2:7]


def req(method, path, token=None, body=None, prefer=None):
    h = {"apikey": anon, "Authorization": f"Bearer {token or anon}", "Content-Type": "application/json"}
    if prefer:
        h["Prefer"] = prefer
    r = urllib.request.Request(url + path, method=method, headers=h, data=None if body is None else json.dumps(body).encode())
    try:
        with urllib.request.urlopen(r, timeout=20) as x:
            t = x.read().decode()
            return x.status, (json.loads(t) if t else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def login(email, pw):
    s, b = req("POST", "/auth/v1/token?grant_type=password", body={"email": email, "password": pw})
    assert s == 200, f"login failed for {email}: {s}"
    return b["access_token"]


ta, tb = login(ea, pa), login(eb, pb)
TABLES = ["projects", "sessions", "events", "reports", "retests", "event_definitions"]
ok = True
for t in TABLES:
    s, rows_a = req("GET", f"/rest/v1/{t}?select=id&limit=1000", ta)
    ids_a = [r["id"] for r in rows_a] if s == 200 else []
    s, rows_b = req("GET", f"/rest/v1/{t}?select=id&limit=1000", tb)
    leaked = [r["id"] for r in rows_b if r["id"] in ids_a] if s == 200 else []
    good = not leaked
    ok &= good
    print(("PASS " if good else "FAIL ") + f"B reads A's {t}: A has {len(ids_a)} rows, B sees {len(leaked)} of them")
    for i in ids_a[:3]:
        s, b = req("PATCH", f"/rest/v1/{t}?id=eq.{i}", tb, {"id": i}, prefer="return=representation")
        s2, b2 = req("DELETE", f"/rest/v1/{t}?id=eq.{i}", tb, prefer="return=representation")
        good = (s in (401, 403, 404) or b in ([], None, "")) and (s2 in (401, 403, 404) or b2 in ([], None, ""))
        ok &= good
        print(("PASS " if good else "FAIL ") + f"B update/delete A's {t} row -> HTTP {s}/{s2}")
print("ALL PASS" if ok else "FAILURES PRESENT")
sys.exit(0 if ok else 1)
