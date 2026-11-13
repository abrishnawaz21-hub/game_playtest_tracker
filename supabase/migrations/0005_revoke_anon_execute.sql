-- 0005: Supabase grants EXECUTE on new functions to anon by default, so "revoke from public" in 0004
-- was not enough. Only sdk_ingest may be called without logging in.
revoke execute on function regenerate_ingest_key(uuid) from anon;
revoke execute on function delete_my_account() from anon;
revoke execute on function event_definitions_lock_name() from anon, authenticated;
