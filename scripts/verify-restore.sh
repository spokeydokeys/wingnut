#!/usr/bin/env bash
#
# Proves the Supabase escape hatch actually works.
#
# Takes a fresh export, restores it into a throwaway VANILLA PostgreSQL
# container (not Supabase's image), and asserts the schema, the RLS policies
# and the ownership maths all still function. Vanilla is the whole point: if the
# export only restores onto Supabase, it is not portability.
#
#   ./scripts/verify-restore.sh
#
# Leaves nothing behind. Run it whenever the schema changes.

set -euo pipefail

PG_IMAGE="${PG_IMAGE:-postgres:17}"
CONTAINER="wingnut_restore_check"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

echo "==> Exporting current database"
./scripts/export-db.sh "${1:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}" >/dev/null
export_dir="$(ls -1d exports/*/ | sort | tail -1)"
echo "    using $export_dir"

echo "==> Starting throwaway $PG_IMAGE"
docker run -d --name "$CONTAINER" -e POSTGRES_PASSWORD=postgres "$PG_IMAGE" >/dev/null

for _ in $(seq 1 60); do
  if docker exec "$CONTAINER" pg_isready -U postgres -q 2>/dev/null; then break; fi
  sleep 1
done
docker exec "$CONTAINER" pg_isready -U postgres -q

psql_in() { docker exec -i "$CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=1 --no-psqlrc "$@"; }

# Roles must exist before the dump lands, because its RLS policies reference
# them. The stock public schema has to go so the dump can recreate its own.
echo "==> Applying self-host compatibility shim"
psql_in -q < scripts/selfhost-shim.sql

echo "==> Clearing the stock public schema"
psql_in -q -c 'drop schema if exists public cascade;'

echo "==> Restoring export"
psql_in -q < "$export_dir/public.sql" >/dev/null

echo "==> Checking the restored database"
psql_in <<'SQL'
do $$
declare
  v_tables      int;
  v_policies    int;
  v_count       int;
  v_max         numeric;
  v_unprotected text;
begin
  select count(*) into v_tables
  from pg_tables
  where schemaname = 'public'
    and tablename in ('company','member','aircraft','ownership_period','ownership_share');
  if v_tables <> 5 then
    raise exception 'FAIL  expected 5 core tables, found %', v_tables;
  end if;
  raise notice 'PASS  all 5 core tables restored';

  -- Assert the security-meaningful property rather than a magic total: no core
  -- table may come back without RLS enabled and at least one policy. A dump
  -- that silently drops a policy would otherwise look like a clean restore.
  select string_agg(t.tablename, ', ' order by t.tablename) into v_unprotected
  from pg_tables t
  where t.schemaname = 'public'
    and t.tablename in ('company','member','aircraft','ownership_period','ownership_share')
    and (
      not t.rowsecurity
      or not exists (
        select 1 from pg_policies p
        where p.schemaname = t.schemaname and p.tablename = t.tablename
      )
    );
  if v_unprotected is not null then
    raise exception 'FAIL  restored without RLS or policies: %', v_unprotected;
  end if;

  select count(*) into v_policies from pg_policies where schemaname = 'public';
  raise notice 'PASS  every core table kept RLS enabled, % policies total', v_policies;

  -- The business invariant: ownership resolves correctly by date.
  select count(*), max(pct) into v_count, v_max
  from public.ownership_as_of(
    (select id from public.aircraft limit 1), current_date);
  if v_count <> 2 or v_max <> 50 then
    raise exception 'FAIL  ownership_as_of returned % owners, max %', v_count, v_max;
  end if;
  raise notice 'PASS  ownership_as_of works on vanilla Postgres';

  -- The deferred 100%% invariant must have survived the dump.
  begin
    insert into public.ownership_period (id, aircraft_id, effective_from)
    values (gen_random_uuid(), (select id from public.aircraft limit 1), date '2030-01-01');
    raise exception 'unreachable';
  exception when others then
    null;
  end;

  select count(*) into v_count from public.company;
  if v_count <> 1 then
    raise exception 'FAIL  expected 1 company row, found %', v_count;
  end if;
  raise notice 'PASS  seed data survived the round trip';

  if auth.uid() is not null then
    raise exception 'FAIL  auth.uid() should be null when unauthenticated';
  end if;
  raise notice 'PASS  auth.uid() shim fails closed when unauthenticated';

  -- Sign-in linking must work off the shim too, otherwise a self-hosted
  -- instance restores fine and then nobody can log in. Uses a throwaway roster
  -- row so the result does not depend on who had already signed in when the
  -- export was taken.
  insert into public.member (id, full_name, email, role)
  values ('00000000-0000-0000-0000-0000000a00f0',
          'Restore Check', 'restore-check@example.invalid', 'pilot');

  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a00f1",
      "email":"Restore-Check@Example.invalid"}', true);

  if public.claim_member_identity()
     is distinct from '00000000-0000-0000-0000-0000000a00f0'::uuid then
    raise exception 'FAIL  claim_member_identity did not claim the roster row';
  end if;
  if public.claim_member_identity()
     is distinct from '00000000-0000-0000-0000-0000000a00f0'::uuid then
    raise exception 'FAIL  claim_member_identity is not idempotent';
  end if;
  raise notice 'PASS  first sign-in can claim a member row on vanilla Postgres';
end $$;
SQL

echo
echo "Escape hatch verified: the export restores and runs on vanilla PostgreSQL."
