-- Supabase compatibility shim for vanilla PostgreSQL.
--
-- The application schema is plain PostgreSQL except for two things it inherits
-- from Supabase: the roles its RLS policies are granted to, and auth.uid().
-- This file supplies both, so a pg_dump taken from Supabase restores and runs
-- on self-hosted Postgres unchanged.
--
-- This IS the self-hosting migration path, and scripts/verify-restore.sh runs
-- it on every check so the escape hatch cannot quietly rot.

-- Roles that RLS policies are granted to. nologin: these are authorisation
-- roles that a connection switches into, never connects as directly.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end $$;

create schema if not exists auth;

-- Same contract as Supabase's auth.uid(): read the subject claim of the
-- verified JWT, which the connection pooler or API layer sets per request as
-- the request.jwt.claims GUC. Returns null when unauthenticated, which makes
-- every policy in the app fail closed.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(
    coalesce(
      current_setting('request.jwt.claim.sub', true),
      current_setting('request.jwt.claims', true)::jsonb ->> 'sub'
    ),
    ''
  )::uuid;
$$;

grant usage on schema auth to anon, authenticated, service_role;

-- Deliberately no grant on schema public here: this file must run BEFORE the
-- dump is restored (the dump's RLS policies reference the roles above, so they
-- have to exist first), and at that point public has been dropped so the dump
-- can recreate it. Vanilla PostgreSQL grants USAGE on public to PUBLIC anyway.
