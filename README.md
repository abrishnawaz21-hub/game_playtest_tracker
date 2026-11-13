# Game Playtest Tracker (40% build)

Flutter Android dashboard + Supabase backend + a script standing in for the Unity SDK.

## Setup
1. Create a free project at supabase.com. In Authentication > Providers > Email, turn OFF "Confirm email" for the demo.
2. SQL Editor: paste and run `supabase/schema.sql`.
3. Project Settings > API: copy the Project URL and the anon/publishable key.
4. Run the app:
   `flutter run --dart-define=SUPABASE_URL=<url> --dart-define=SUPABASE_ANON_KEY=<key>`
5. Sign up, create a project, tap the key icon to copy its SDK key.
6. Send test data: `python tools/fake_sdk.py <url> <key> <sdk-key>`
   Pull down to refresh the Reports tab; open the report to see its events.

Built: auth, projects, reports + status filter, report details with event timeline,
status update, sessions + session details. Not built (planned): Unity SDK and game,
retests, build comparison, Event Studio, tester pages, profile.
