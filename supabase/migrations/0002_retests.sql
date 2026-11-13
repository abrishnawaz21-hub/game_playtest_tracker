-- Run once in Supabase > SQL Editor (after schema.sql).
create table retests (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references reports(id) on delete cascade,
  project_id uuid not null references projects(id) on delete cascade,
  build_version text not null,
  result text not null check (result in ('Not Tested','Reproduced','Not Reproduced')),
  note text,
  created_at timestamptz not null default now()
);
create index on retests(report_id, created_at desc);

alter table retests enable row level security;
grant select, insert on retests to authenticated;

create policy retests_read on retests for select to authenticated
  using (exists (select 1 from projects p where p.id = project_id and p.owner_id = auth.uid()));
create policy retests_insert on retests for insert to authenticated
  with check (
    exists (select 1 from reports r join projects p on p.id = r.project_id
            where r.id = report_id and r.project_id = retests.project_id and p.owner_id = auth.uid()));
