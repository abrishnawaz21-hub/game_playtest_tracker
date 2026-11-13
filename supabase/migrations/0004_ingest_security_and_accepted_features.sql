-- 0004: hardened ingestion, severity / device info, report redaction, account deletion.
-- Run once in Supabase > SQL Editor after 0001-0003. Idempotent where possible.
-- NOT YET EXECUTED against the live project when this file was written.

-- ---------------------------------------------------------------- columns
alter table reports  add column if not exists severity text not null default 'Medium'
  check (severity in ('Low','Medium','High','Critical'));
alter table reports  add column if not exists device_model text;
alter table reports  add column if not exists android_version text;
alter table reports  add column if not exists redacted boolean not null default false;
alter table reports  add column if not exists severity_rank smallint generated always as (
  case severity when 'Critical' then 4 when 'High' then 3 when 'Medium' then 2 else 1 end) stored;
alter table reports  add column if not exists client_report_id text;
alter table sessions add column if not exists client_session_id text;
alter table sessions add column if not exists device_model text;
alter table sessions add column if not exists android_version text;
alter table events   add column if not exists client_event_id text;

-- Duplicate protection: a retry that repeats an id is ignored, not stored twice.
create unique index if not exists sessions_client_uid on sessions(project_id, client_session_id)
  where client_session_id is not null;
create unique index if not exists reports_client_uid on reports(project_id, client_report_id)
  where client_report_id is not null;
create unique index if not exists events_client_uid on events(session_id, client_event_id)
  where client_event_id is not null;

-- ---------------------------------------------------------------- rate limit log
create table if not exists ingest_log (
  project_id uuid not null references projects(id) on delete cascade,
  at timestamptz not null default now()
);
create index if not exists ingest_log_project_at on ingest_log(project_id, at desc);
alter table ingest_log enable row level security;
revoke all on ingest_log from anon, authenticated;   -- no policies: only the functions below touch it

-- ---------------------------------------------------------------- ingestion
-- The game calls this with the project's INGEST key. The key can only send data:
-- it cannot read anything, and this function returns only the new session id.
create or replace function sdk_ingest(
  p_ingest_key uuid,
  p_build text,
  p_tester text,
  p_client_session_id text,
  p_events jsonb,
  p_description text default null,
  p_category text default 'Other',
  p_severity text default 'Medium',
  p_device_model text default null,
  p_android_version text default null,
  p_client_report_id text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_project uuid; v_session uuid; e jsonb; v_name text; v_at timestamptz; v_props jsonb;
begin
  select id into v_project from projects where sdk_key = p_ingest_key;
  if v_project is null then raise exception 'invalid_request'; end if;

  -- rate limit: at most 60 submissions per project per minute
  if (select count(*) from ingest_log where project_id = v_project and at > now() - interval '1 minute') >= 60 then
    raise exception 'rate_limited';
  end if;
  insert into ingest_log(project_id) values (v_project);
  delete from ingest_log where project_id = v_project and at < now() - interval '1 hour';

  -- validate payload
  if coalesce(length(trim(p_build)), 0) not between 1 and 40 then raise exception 'invalid_request'; end if;
  if coalesce(length(trim(p_tester)), 0) not between 1 and 64 then raise exception 'invalid_request'; end if;
  if p_events is null or jsonb_typeof(p_events) <> 'array' or jsonb_array_length(p_events) > 200 then
    raise exception 'invalid_request';
  end if;
  if p_description is not null and length(p_description) > 2000 then raise exception 'invalid_request'; end if;
  if p_category not in ('Gameplay','Controls','Visual','Progress','Interface','Other') then p_category := 'Other'; end if;
  if p_severity not in ('Low','Medium','High','Critical') then p_severity := 'Medium'; end if;
  if p_client_session_id is not null and length(p_client_session_id) > 64 then raise exception 'invalid_request'; end if;

  -- session: reuse by client id (idempotent), otherwise create
  if p_client_session_id is not null then
    select id into v_session from sessions where project_id = v_project and client_session_id = p_client_session_id;
  end if;
  if v_session is null then
    insert into sessions(project_id, build_version, tester_id, client_session_id, device_model, android_version)
      values (v_project, trim(p_build), trim(p_tester), p_client_session_id, left(p_device_model, 80), left(p_android_version, 40))
      returning id into v_session;
  end if;

  for e in select * from jsonb_array_elements(p_events) loop
    v_name := e->>'name';
    if v_name is null or v_name !~ '^[a-z][a-z0-9_]{0,63}$' then continue; end if;
    v_props := coalesce(e->'props', '{}'::jsonb);
    if jsonb_typeof(v_props) <> 'object' or octet_length(v_props::text) > 4096 then continue; end if;
    begin v_at := (e->>'at')::timestamptz; exception when others then v_at := null; end;
    if v_at is null or v_at > now() + interval '5 minutes' or v_at < now() - interval '30 days' then v_at := now(); end if;
    insert into events(session_id, project_id, name, props, created_at, client_event_id)
      values (v_session, v_project, v_name, v_props, v_at, left(e->>'eid', 64))
      on conflict do nothing;
  end loop;

  if p_description is not null and length(trim(p_description)) > 0 then
    insert into reports(project_id, session_id, build_version, tester_id, category, severity, description,
                        device_model, android_version, client_report_id)
      values (v_project, v_session, trim(p_build), trim(p_tester), p_category, p_severity, p_description,
              left(p_device_model, 80), left(p_android_version, 40), left(p_client_report_id, 64))
      on conflict do nothing;
  end if;

  update sessions set ended_at = now() where id = v_session;
  return v_session;
end $$;

revoke all on function sdk_ingest from public;
grant execute on function sdk_ingest to anon, authenticated;

-- The first-generation entry point wrote with the same key but had no limits: close it.
revoke execute on function sdk_submit from anon, authenticated;

-- ---------------------------------------------------------------- ingest key
create or replace function regenerate_ingest_key(p_project uuid) returns uuid
language sql security definer set search_path = public as $$
  update projects set sdk_key = gen_random_uuid()
   where id = p_project and owner_id = auth.uid()
  returning sdk_key;
$$;
revoke all on function regenerate_ingest_key from public;
grant execute on function regenerate_ingest_key to authenticated;

-- ---------------------------------------------------------------- delete / redact reports
grant delete on reports to authenticated;
drop policy if exists reports_delete on reports;
create policy reports_delete on reports for delete to authenticated
  using (exists (select 1 from projects p where p.id = project_id and p.owner_id = auth.uid()));
-- Redaction = an ordinary update of description / redacted (covered by reports_update).

-- ---------------------------------------------------------------- event definitions: names are locked
create or replace function event_definitions_lock_name() returns trigger language plpgsql as $$
begin
  if new.name <> old.name then raise exception 'event names are locked'; end if;
  return new;
end $$;
drop trigger if exists event_definitions_lock_name on event_definitions;
create trigger event_definitions_lock_name before update on event_definitions
  for each row execute function event_definitions_lock_name();

-- ---------------------------------------------------------------- account deletion
-- Deletes the caller's projects (and, by cascade, sessions, events, reports, retests, definitions)
-- and then the account itself.
create or replace function delete_my_account() returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  delete from projects where owner_id = auth.uid();
  delete from auth.users where id = auth.uid();
end $$;
revoke all on function delete_my_account from public;
grant execute on function delete_my_account to authenticated;
