-- Run in Supabase > SQL Editor. Read-only. Shows every table's RLS state, policies and grants.

-- 1. RLS enabled? (every row must show rls_enabled = true)
select c.relname as table, c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' order by 1;

-- 2. Every policy
select tablename, policyname, cmd, roles, qual as using_expr, with_check
from pg_policies where schemaname = 'public' order by tablename, cmd, policyname;

-- 3. Table privileges for the two API roles
select table_name, grantee, string_agg(privilege_type, ', ' order by privilege_type) as privileges
from information_schema.role_table_grants
where table_schema = 'public' and grantee in ('anon', 'authenticated')
group by table_name, grantee order by table_name, grantee;

-- 4. Who can run the functions (anon must have sdk_ingest only)
select routine_name, grantee
from information_schema.routine_privileges
where routine_schema = 'public' and grantee in ('anon', 'authenticated') order by routine_name, grantee;
