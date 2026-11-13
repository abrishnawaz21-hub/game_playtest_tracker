"""Stand-in for the Unity SDK: plays a short session and files a bug report.

Usage: python tools/fake_sdk.py <SUPABASE_URL> <ANON_KEY> <PROJECT_SDK_KEY> [build] [tester]
The ingest key is shown in the app: Game > Dashboard > SDK setup. Needs migration 0004. Uses only the standard library.
"""
import json
import sys
import urllib.request
from datetime import datetime, timedelta, timezone

url, anon, sdk_key = sys.argv[1:4]
build = sys.argv[4] if len(sys.argv) > 4 else "0.8.1"
tester = sys.argv[5] if len(sys.argv) > 5 else "tester-7f3a"

t0 = datetime.now(timezone.utc) - timedelta(minutes=2)
steps = [
    ("game_started", {}),
    ("level_started", {"level": 1}),
    ("button_clicked", {"button": "open_door"}),
    ("gameplay_action", {"action": "pick_key", "x": 4, "y": 9}),
    ("gameplay_action", {"action": "enter_wall", "x": 5, "y": 9}),
    ("issue_reported", {}),
]
events = [
    {"name": n, "props": p, "at": (t0 + timedelta(seconds=i * 20)).isoformat()}
    for i, (n, p) in enumerate(steps)
]
import uuid
sid = uuid.uuid4().hex
for i, e in enumerate(events):
    e["eid"] = f"{sid}-{i}"          # idempotency id: a retry never stores an event twice
body = {
    "p_ingest_key": sdk_key, "p_build": build, "p_tester": tester, "p_events": events,
    "p_client_session_id": sid, "p_client_report_id": sid + "-r",
    "p_description": "I walked through a wall near the key room and fell out of the maze.",
    "p_category": "Gameplay", "p_severity": "Critical",
    "p_device_model": "fake-sdk", "p_android_version": "script",
}
req = urllib.request.Request(
    f"{url}/rest/v1/rpc/sdk_ingest", data=json.dumps(body).encode(), method="POST",
    headers={"apikey": anon, "Authorization": f"Bearer {anon}", "Content-Type": "application/json"},
)
try:
    print("session id:", urllib.request.urlopen(req, timeout=15).read().decode())
except Exception as ex:
    print("failed:", ex, getattr(ex, "read", lambda: b"")().decode())
    sys.exit(1)
