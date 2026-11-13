# Game Playtest Tracker: Version 1 status

Version 1 is for a single developer. The dashboard has 20 developer-app screens plus the in-game report form.

## Real in Version 1 vs mocked
| Area | Status |
|---|---|
| Email sign-in, sign-up, log out | Real (tested on emulator) |
| Forgot password email + deep link | Code written; email round-trip NOT tested on a device |
| Delete account (in app) | Screen tested up to the confirm box (button disabled until DELETE is typed); the deletion itself was NOT run, to protect the real account |
| Social sign-in | Removed (accepted change) |
| Projects, reports, sessions, events, report status | Real (tested) |
| Retests, event definitions | Real (tested) |
| Compare builds | Real, computed from stored data |
| Ingest via `sdk_ingest` (ingest key, limits, idempotency) | Migrations 0004+0005 run. Tested: valid call accepted, wrong key refused, 5 bad payloads refused/skipped, rate limit (59 ok / 11 refused), old sdk_submit blocked. Duplicate-id behaviour NOT tested |
| Unity SDK + Unity test game | Source written; NEVER compiled or run (no Unity here) |
| Flutter test game (Snake Rush) | Real; sends through the new function with fallback to the old one |
| CSV export, severity filter/sort, date range, Load more | Real in the app; severity needs migration 0004 |
| Photo upload, push alerts, daily summary | Not built / removed |

## Privacy and retention
Reports and events are used only by the game's developer to investigate problems. Testers are identified by a random install ID. Data is kept while the developer keeps the game; a developer can delete or redact any report; deleting the account deletes everything.

## Ingest key
Formerly "client key". It can only send data through `sdk_ingest`; it reads nothing. It is visible inside a game build, so it is not a secret. The backend limits it to 60 submissions per minute per project, and the developer can regenerate it in SDK setup.

## Migrations (run in order in Supabase SQL Editor)
`supabase/migrations/0001..0005`, all run on the live project.

## Proof tools
- `supabase/audit/rls_audit.sql`: shows RLS state, policies and grants.
- `tools/rls_probe.py URL ANON_KEY`: anonymous-caller probe (ran after 0005: 31/31 passed).
- `tools/rls_two_developers.py`: developer A vs B isolation (needs two accounts; NOT run).

## Release build
`flutter build apk --release --split-per-abi --obfuscate --split-debug-info=docs/debug-info`. Keystore: NOT created; release is still signed with the debug key. Do not publish until a keystore is set up (keep `key.properties` and `*.jks` out of Git; .gitignore already excludes them).
