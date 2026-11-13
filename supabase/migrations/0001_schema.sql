-- Game Playtest Tracker schema. Paste into Supabase > SQL Editor > Run.

create table projects (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id),
  name text not null check (length(trim(name)) > 0),
  description text,
  sdk_key uuid not null unique default gen_random_uuid(),
  created_at timestamptz not null default now()
);

create table sessions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  build_version text not null,
  tester_id text not null,
  started_at timestamptz not null default now(),
  ended_at timestamptz
);

create table events (
  id bigint generated always as identity primary key,
  session_id uuid not null references sessions(id) on delete cascade,
  project_id uuid not null references projects(id) on delete cascade,
  name text not null,
  props jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create table reports (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  session_id uuid references sessions(id) on delete set null,
  build_version text not null,
  tester_id text not null,
  category text not null default 'Other',
  description text not null,
  status text not null default 'Open' check (status in ('Open','In Progress','Resolved')),
  created_at timestamptz not null default now()
);

create index on events(session_id, created_at);
create index on reports(project_id, status, created_at desc);
create index on sessions(project_id, started_at desc);

alter table projects enable row level security;
alter table sessions enable row level security;
alter table events enable row level security;
alter table reports enable row level security;

-- Developers: only their own projects and the data under them.
grant select, insert, update on projects to authenticated;
grant select on sessions, events to authenticated;
grant select, update on reports to authenticated;

create policy projects_owner on projects for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy sessions_read on sessions for select to authenticated
  using (exists (select 1 from projects p where p.id = project_id and p.owner_id = auth.uid()));
create policy events_read on events for select to authenticated
  using (exists (select 1 from projects p where p.id = project_id and p.owner_id = auth.uid()));
create policy reports_read on reports for select to authenticated
  using (exists (select 1 from projects p where p.id = project_id and p.owner_id = auth.uid()));
create policy reports_update on reports for update to authenticated
  using (exists (select 1 from projects p where p.id = project_id and p.owner_id = auth.uid()))
  with check (exists (select 1 from projects p where p.id = project_id and p.owner_id = auth.uid()));

-- SDK entry point: the game calls this with the project's sdk_key (no login).
-- Validates the key, creates the session, stores events and an optional report.
create or replace function sdk_submit(
  p_sdk_key uuid, p_build text, p_tester text,
  p_events jsonb, p_description text default null, p_category text default 'Other'
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_project uuid; v_session uuid; e jsonb;
begin
  select id into v_project from projects where sdk_key = p_sdk_key;
  if v_project is null then raise exception 'invalid sdk key'; end if;
  if coalesce(trim(p_build), '') = '' or coalesce(trim(p_tester), '') = '' then
    raise exception 'build and tester are required';
  end if;
  if jsonb_typeof(p_events) <> 'array' or jsonb_array_length(p_events) > 200 then
    raise exception 'events must be an array of at most 200';
  end if;

  insert into sessions(project_id, build_version, tester_id)
    values (v_project, p_build, p_tester) returning id into v_session;

  for e in select * from jsonb_array_elements(p_events) loop
    if coalesce(e->>'name','') = '' then continue; end if;
    insert into events(session_id, project_id, name, props, created_at)
      values (v_session, v_project, left(e->>'name', 64),
              coalesce(e->'props', '{}'), coalesce((e->>'at')::timestamptz, now()));
  end loop;

  if p_description is not null and length(trim(p_description)) > 0 then
    insert into reports(project_id, session_id, build_version, tester_id, category, description)
      values (v_project, v_session, p_build, p_tester, left(p_category, 32), left(p_description, 2000));
  end if;
  update sessions set ended_at = now() where id = v_session;
  return v_session;
end $$;

revoke all on function sdk_submit from public;
grant execute on function sdk_submit to anon, authenticated;
