-- Run once in Supabase > SQL Editor (after schema.sql). Powers Event Studio.
create table event_definitions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  name text not null check (name ~ '^[a-z][a-z0-9_]{0,63}$'),
  description text,
  category text not null default 'Gameplay',
  props jsonb not null default '[]',
  created_at timestamptz not null default now(),
  unique (project_id, name)
);

alter table event_definitions enable row level security;
grant select, insert, update, delete on event_definitions to authenticated;

create policy defs_owner on event_definitions for all to authenticated
  using (exists (select 1 from projects p where p.id = project_id and p.owner_id = auth.uid()))
  with check (exists (select 1 from projects p where p.id = project_id and p.owner_id = auth.uid()));
