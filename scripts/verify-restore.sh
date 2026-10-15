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
  v_shares      int;
  v_whole       int;
  v_refused     boolean;
  v_unprotected text;
  v_flight      public.flight;
  v_again       public.flight;
  v_item        uuid;
  v_interval    numeric;
  v_hours       numeric;
  v_state       text;
  v_ok          boolean;
  v_base        numeric;
  v_admin       uuid := '00000000-0000-0000-0000-0000000a00fa';
  v_pilot       uuid := '00000000-0000-0000-0000-0000000a00f0';
  v_air         uuid;
  v_month       date;
  v_billed      uuid;
  v_invoice     uuid;
  v_number      bigint;
  v_wet         numeric;
  v_total       numeric;
  v_blocked     text;
begin
  select count(*) into v_tables
  from pg_tables
  where schemaname = 'public'
    and tablename in ('company','member','aircraft','ownership_period','ownership_share',
                      'gl_account','rate_schedule','rate_component',
                      'fixed_cost_schedule','fixed_cost',
                      'invoice','invoice_counter','ledger_entry',
                      'place','flight','flight_fix','api_token',
                      'snag','tach_reading','maintenance_item','maintenance_event',
                      'aircraft_note','task','task_series','expense','booking');
  if v_tables <> 26 then
    raise exception 'FAIL  expected 26 core tables, found %', v_tables;
  end if;
  raise notice 'PASS  all 26 core tables restored';

  -- Assert the security-meaningful property rather than a magic total: no core
  -- table may come back without RLS enabled and at least one policy. A dump
  -- that silently drops a policy would otherwise look like a clean restore.
  --
  -- invoice_counter is the one deliberate exception: it has RLS and no policy
  -- at all, because numbers are only ever allocated through the security
  -- definer function. RLS with no policy denies everyone, which is the intent.
  select string_agg(t.tablename, ', ' order by t.tablename) into v_unprotected
  from pg_tables t
  where t.schemaname = 'public'
    and t.tablename in ('company','member','aircraft','ownership_period','ownership_share',
                        'gl_account','rate_schedule','rate_component',
                        'fixed_cost_schedule','fixed_cost',
                        'invoice','ledger_entry',
                        'place','flight','flight_fix','api_token',
                        'snag','tach_reading','maintenance_item','maintenance_event',
                        'aircraft_note','task','task_series','expense','booking')
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

  if not (select rowsecurity from pg_tables
           where schemaname = 'public' and tablename = 'invoice_counter') then
    raise exception 'FAIL  invoice_counter restored without RLS';
  end if;
  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename = 'invoice_counter') then
    raise exception 'FAIL  invoice_counter gained a policy; it must deny everyone';
  end if;

  -- security_invoker is an attribute of the view, so it has to survive the dump
  -- too. If it came back off, the restored instance would run these views as
  -- their owner and show every owner the whole pool's ledger.
  select string_agg(c.relname, ', ' order by c.relname) into v_unprotected
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in ('ledger_entry_posted','gl_journal','flight_running',
                      'maintenance_status')
    -- Parsed rather than string-matched: Postgres stores the option as it was
    -- written, so this is 'on' here and could equally be 'true'.
    and not coalesce((
      select o.option_value::boolean
      from pg_options_to_table(c.reloptions) o
      where o.option_name = 'security_invoker'
    ), false);
  if v_unprotected is not null then
    raise exception 'FAIL  views restored without security_invoker: %', v_unprotected;
  end if;
  raise notice 'PASS  every view kept security_invoker through the dump';

  select count(*) into v_policies from pg_policies where schemaname = 'public';
  raise notice 'PASS  every core table kept RLS enabled, % policies total', v_policies;

  -- The business invariant: ownership resolves correctly by date, and the
  -- resolver carries the denominator so the fraction is not left to the caller.
  select count(*), max(o.shares), max(o.total_shares), max(o.fraction)
    into v_count, v_shares, v_whole, v_max
  from public.ownership_as_of(
    (select id from public.aircraft limit 1), current_date) o;
  if v_count <> 2 or v_shares * 2 <> v_whole or v_max <> 0.5 then
    raise exception
      'FAIL  ownership_as_of returned % owners, largest % of %, fraction %',
      v_count, v_shares, v_whole, v_max;
  end if;
  raise notice 'PASS  ownership_as_of works on vanilla Postgres';

  -- The deferred sums-to-total invariant must have survived the dump. One
  -- share short, not zero: an empty period is legal and is how a period is
  -- cleared before it is deleted, so zero would prove nothing.
  v_refused := false;
  begin
    insert into public.ownership_period (id, aircraft_id, effective_from)
    values ('00000000-0000-0000-0000-0000000dead9',
            (select id from public.aircraft limit 1), date '2030-01-01');
    insert into public.ownership_share (period_id, member_id, shares)
    values ('00000000-0000-0000-0000-0000000dead9',
            (select id from public.member order by id limit 1),
            v_whole - 1);
    set constraints all immediate;
  exception when others then
    v_refused := true;
  end;
  if not v_refused then
    raise exception 'FAIL  a period one share short of % was accepted', v_whole;
  end if;
  raise notice 'PASS  the sums-to-total trigger survived the dump';

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

  -- The money layer must work too, not just restore. Build one invoice end to
  -- end on the vanilla instance: rate resolution, gapless numbering, the
  -- draft/issued balance rule, the immutability trigger and a balanced journal.
  if public.wet_rate_as_of(
       (select id from public.aircraft limit 1), current_date) is null then
    raise exception 'FAIL  wet_rate_as_of returned null on vanilla Postgres';
  end if;

  insert into public.invoice (id, company_id, member_id, period_month)
  values ('00000000-0000-0000-0000-0000000f00f0',
          (select id from public.company limit 1),
          '00000000-0000-0000-0000-0000000a00f0',
          date '2029-01-01');

  insert into public.ledger_entry
    (id, company_id, member_id, invoice_id, kind, entry_date, description,
     amount, gl_account_code)
  values ('00000000-0000-0000-0000-0000000e00f0',
          (select id from public.company limit 1),
          '00000000-0000-0000-0000-0000000a00f0',
          '00000000-0000-0000-0000-0000000f00f0',
          'flight_charge', date '2029-01-15', 'Restore check flight',
          100.00, '4100');

  if public.member_balance('00000000-0000-0000-0000-0000000a00f0') <> 0 then
    raise exception 'FAIL  a draft invoice counted toward the balance after restore';
  end if;

  update public.invoice
     set status    = 'issued',
         number    = public.next_invoice_number(
                       (select id from public.company limit 1)),
         issued_at = now()
   where id = '00000000-0000-0000-0000-0000000f00f0';

  if public.member_balance('00000000-0000-0000-0000-0000000a00f0') <> 100.00 then
    raise exception 'FAIL  issuing did not move the balance after restore';
  end if;

  -- The guard trigger has to have come across with the dump.
  begin
    update public.ledger_entry set amount = 1.00
     where id = '00000000-0000-0000-0000-0000000e00f0';
    raise exception 'FAIL  an issued invoice line was editable after restore';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;

  -- And the sign convention.
  begin
    insert into public.ledger_entry
      (company_id, member_id, kind, entry_date, description, amount, gl_account_code)
    values ((select id from public.company limit 1),
            '00000000-0000-0000-0000-0000000a00f0',
            'payment', date '2029-01-20', 'Backwards payment', 50.00, '1000');
    raise exception 'FAIL  a positive payment was accepted after restore';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;

  select coalesce(sum(debit_credit), 0) into v_max
  from public.gl_journal where entry_date >= date '2029-01-01';
  if v_max <> 0 then
    raise exception 'FAIL  the restored journal nets to %', v_max;
  end if;

  raise notice 'PASS  the ledger bills and balances on vanilla Postgres';

  -- The timer is the one thing an owner touches every flight, so prove it flies
  -- on the restored instance: token auth, the one-open-flight index, the
  -- derived-hours trigger and both rounding rules, end to end.
  insert into public.api_token (member_id, token_hash, label)
  values ('00000000-0000-0000-0000-0000000a00f0', repeat('9', 64), 'restore check');

  v_flight := public.timer_start(repeat('9', 64), 48.65, -123.4, 12);
  if v_flight.end_at is not null or v_flight.billed_hours is not null then
    raise exception 'FAIL  a freshly started flight is already finished';
  end if;

  -- A second Start must not open a second flight.
  v_again := public.timer_start(repeat('9', 64));
  if v_again.id <> v_flight.id then
    raise exception 'FAIL  a second Start opened another flight after restore';
  end if;

  -- now() is the transaction timestamp, so wind the clock back 48 minutes
  -- rather than trying to let time pass inside a single transaction.
  update public.flight set start_at = start_at - interval '48 minutes'
   where id = v_flight.id;

  v_flight := public.timer_stop(repeat('9', 64), 48.42, -123.37, 9);

  -- 0.8 hr exactly: billed rounds up to 0.8, tach is 0.8/1.3 = 0.615 -> 0.6.
  if (v_flight.billed_hours, v_flight.est_tach_hours, v_flight.tach_factor_used)
     is distinct from (0.80, 0.60, 1.300) then
    raise exception 'FAIL  a 48 minute flight priced as %/% on factor % after restore',
      v_flight.billed_hours, v_flight.est_tach_hours, v_flight.tach_factor_used;
  end if;

  select count(*) into v_count from public.flight_fix where flight_id = v_flight.id;
  if v_count <> 2 then
    raise exception 'FAIL  % GPS fix(es) stored after restore', v_count;
  end if;

  -- A revoked token must stop working, or the escape hatch leaks a credential.
  update public.api_token set revoked_at = now() where token_hash = repeat('9', 64);
  begin
    perform public.member_for_token_hash(repeat('9', 64));
    raise exception 'FAIL  a revoked token still authenticated after restore';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;

  raise notice 'PASS  the flight timer runs on vanilla Postgres';

  -- The Aircraft tab is almost entirely derived -- the tach estimate, the
  -- status view, the clearing stamp -- so a restore that brought the tables
  -- across but not the arithmetic would look healthy and quietly stop tracking
  -- engine life. Exercise the whole chain.

  -- aircraft_today() must read the aeroplane's zone, not the container's. This
  -- throwaway runs in UTC, where it is already tomorrow after 5pm Pacific.
  if public.aircraft_today()
     is distinct from (now() at time zone 'America/Vancouver')::date then
    raise exception 'FAIL  aircraft_today() says % after restore',
      public.aircraft_today();
  end if;

  -- The flight stopped above carried no meter reading, so the estimate is the
  -- last real reading plus the flying since -- strictly more than the reading.
  select r.reading into v_max
  from public.tach_reading r
  where r.aircraft_id = (select id from public.aircraft limit 1)
  order by r.read_at desc, r.created_at desc limit 1;

  if public.aircraft_tach_estimate((select id from public.aircraft limit 1))
     <= v_max then
    raise exception 'FAIL  flying since the last reading did not move the estimate';
  end if;

  -- A tach typed on the Confirm screen is mirrored into tach_reading by the
  -- database, dated at the flight's end so the flight is not counted on top of
  -- its own reading.
  update public.flight set actual_tach_hours = 800.00 where id = v_flight.id;

  select r.reading, r.read_at = v_flight.end_at
    into v_hours, v_ok
  from public.tach_reading r where r.flight_id = v_flight.id;
  if v_hours is distinct from 800.00 or not coalesce(v_ok, false) then
    raise exception 'FAIL  a confirmed tach restored as % at the wrong moment', v_hours;
  end if;
  if public.aircraft_tach_estimate((select id from public.aircraft limit 1))
     is distinct from 800.00 then
    raise exception 'FAIL  a flight counted inside its own reading after restore';
  end if;

  -- A newer reading IS the reset: dated ahead of every flight, nothing is
  -- added to it.
  insert into public.tach_reading (aircraft_id, reading, read_at, read_by)
  values ((select id from public.aircraft limit 1), 900.00,
          now() + interval '1 day', '00000000-0000-0000-0000-0000000a00f0');

  if public.aircraft_tach_estimate((select id from public.aircraft limit 1))
     is distinct from 900.00 then
    raise exception 'FAIL  a fresh reading left the estimate at % after restore',
      public.aircraft_tach_estimate((select id from public.aircraft limit 1));
  end if;

  -- The recurring tach task -- the prop hub grease -- is now long overdue
  -- against that reading, and marking it done is what resets its counter.
  select i.id, i.interval_hours into v_item, v_interval
  from public.maintenance_item i
  where i.basis = 'tach' and i.kind = 'recurring_task' and i.is_active
  order by i.sort_order limit 1;
  if v_item is null then
    raise exception 'FAIL  no recurring tach item survived the restore';
  end if;

  select s.state into v_state from public.maintenance_status s where s.id = v_item;
  if v_state is distinct from 'overdue' then
    raise exception 'FAIL  400 hr past its interval the grease reads %', v_state;
  end if;

  insert into public.maintenance_event (item_id, done_on, tach, done_by)
  values (v_item, public.aircraft_today(), 900.00,
          '00000000-0000-0000-0000-0000000a00f0');

  select s.hours_used, s.hours_remaining, s.state
    into v_max, v_hours, v_state
  from public.maintenance_status s where s.id = v_item;
  if (v_max, v_hours, v_state) is distinct from (0.00, v_interval, 'ok') then
    raise exception 'FAIL  after marking done the item reads %/%/% after restore',
      v_max, v_hours, v_state;
  end if;

  -- Clearing a snag must still be stamped by the database rather than by the
  -- caller, or a self-hosted instance would accept whatever it was told.
  insert into public.snag (id, aircraft_id, title, reported_by)
  values ('00000000-0000-0000-0000-0000000500f0',
          (select id from public.aircraft limit 1), 'Restore check snag',
          '00000000-0000-0000-0000-0000000a00f0');

  update public.snag
     set status     = 'cleared',
         cleared_by = (select id from public.member
                        where id <> '00000000-0000-0000-0000-0000000a00f0' limit 1),
         cleared_at = timestamptz '2001-01-01 00:00:00+00'
   where id = '00000000-0000-0000-0000-0000000500f0';

  select s.cleared_by into v_item from public.snag s
   where s.id = '00000000-0000-0000-0000-0000000500f0';
  if v_item is distinct from '00000000-0000-0000-0000-0000000a00f0'::uuid then
    raise exception 'FAIL  the restored snag says % cleared it', v_item;
  end if;

  -- A snag's re-check is arithmetic on a remembered datum, so it is the kind of
  -- thing that restores as a column and quietly stops working. "Check again in
  -- 10 hr" has to be armed from the tach as it stood, and has to hold still: a
  -- datum re-stamped on every save pushes the reminder further away each time
  -- anyone opens the snag.
  insert into public.snag
    (id, aircraft_id, title, status, reported_by,
     recheck_tach_hours, recheck_tach_base)
  values ('00000000-0000-0000-0000-0000000500f1',
          (select id from public.aircraft limit 1), 'Restore check watch',
          'watch', '00000000-0000-0000-0000-0000000a00f0', 10.0, 0.00);

  select s.recheck_tach_base into v_base from public.snag s
   where s.id = '00000000-0000-0000-0000-0000000500f1';
  if v_base is distinct from 900.00 then
    raise exception 'FAIL  the restored re-check was armed at % not the tach estimate',
      v_base;
  end if;

  -- The meter moves on. Re-saving the snag must not re-arm it.
  insert into public.tach_reading (aircraft_id, reading, read_at, read_by)
  values ((select id from public.aircraft limit 1), 950.00,
          now() + interval '2 days', '00000000-0000-0000-0000-0000000a00f0');

  update public.snag set notes = 'Still watching it'
   where id = '00000000-0000-0000-0000-0000000500f1';

  select s.recheck_tach_base into v_base from public.snag s
   where s.id = '00000000-0000-0000-0000-0000000500f1';
  if v_base is distinct from 900.00 then
    raise exception 'FAIL  re-saving a restored snag moved its datum to %', v_base;
  end if;

  -- And one snag still answers "when should this come back?" one way only.
  begin
    update public.snag set recheck_on = public.aircraft_today()
     where id = '00000000-0000-0000-0000-0000000500f1';
    raise exception 'FAIL  a restored snag waits on hours AND on a date';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;

  raise notice 'PASS  the tach estimate, maintenance status and snag re-checks derive on vanilla Postgres';

  -- Billing is the half of this app whose failure nobody notices for a year: a
  -- restore that brought the tables across but not month_charges() looks
  -- perfectly healthy right up to the first invoice that is wrong. So close a
  -- month end to end here -- pricing, the gapless number, the flight lock, the
  -- four-eyes rule on payments and the settle -- on an instance that has never
  -- run Supabase.
  select a.id into v_air from public.aircraft a limit 1;

  -- Two months back: past, so it is closeable, and not the month the seed
  -- already closed. Derived rather than written down, because a literal month
  -- here would expire.
  v_month := date_trunc('month', public.aircraft_today() - interval '2 months')::date;

  -- The claims are still the pilot's from the sign-in check above, which is
  -- the moment to prove month_charges refuses them somebody else's figures.
  -- SPEC.md 4.6: "only an admin sees all pilots' numbers."
  begin
    perform * from public.month_charges(v_air, v_admin, v_month);
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a restored pilot priced another member''s month';
  end if;

  insert into public.flight (aircraft_id, pilot_member_id, status, start_at, end_at)
  values (v_air, v_pilot, 'confirmed',
          (v_month + 10 + time '10:00') at time zone 'America/Vancouver',
          (v_month + 10 + time '11:24') at time zone 'America/Vancouver')
  returning id into v_billed;

  -- Closing needs an admin, and whether either seeded owner's row had been
  -- claimed by a browser before the export was taken is not this script's
  -- business. So it brings its own, through the same sign-in path.
  insert into public.member (id, full_name, email, role)
  values (v_admin, 'Restore Admin', 'restore-admin@example.invalid', 'admin');

  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a00fb",
      "email":"restore-admin@example.invalid"}', true);
  if public.claim_member_identity() is distinct from v_admin then
    raise exception 'FAIL  the restored admin could not claim its roster row';
  end if;

  v_count := public.close_month(v_air, v_month);
  if v_count = 0 then
    raise exception 'FAIL  closing % built no drafts after restore', v_month;
  end if;

  select i.id into v_invoice from public.invoice i
   where i.member_id = v_pilot and i.period_month = v_month;
  if v_invoice is null then
    raise exception 'FAIL  the member who flew got no draft after restore';
  end if;

  -- 1.4 hr at the wet rate, and nothing else: this member owns none of the
  -- aeroplane, so they pay for flying and not for the hangar. Which also shows
  -- fixed_cost_share came back able to say "none of it".
  v_wet := public.wet_rate_as_of(v_air, v_month);
  if public.invoice_total(v_invoice) is distinct from round(1.4 * v_wet, 2) then
    raise exception 'FAIL  1.4 hr at % came to % after restore',
      v_wet, public.invoice_total(v_invoice);
  end if;
  select count(*) into v_count from public.ledger_entry
   where invoice_id = v_invoice and kind <> 'flight_charge';
  if v_count <> 0 then
    raise exception 'FAIL  a non-owner was billed % fixed-cost line(s) after restore', v_count;
  end if;

  v_number := public.issue_invoice(v_invoice);
  if v_number is null then
    raise exception 'FAIL  issuing allocated no number after restore';
  end if;

  -- The lock: the flight that was priced is now on the invoice that priced it,
  -- so next month cannot bill it again.
  select f.status::text, f.invoice_id into v_state, v_item
  from public.flight f where f.id = v_billed;
  if (v_state, v_item) is distinct from ('billed', v_invoice) then
    raise exception 'FAIL  the billed flight restored as % against %', v_state, v_item;
  end if;

  -- SPEC.md 4.6: "a sent invoice never changes silently". Closing again must
  -- step over it -- and the figure proves it did, because the flight is locked
  -- now, so a rebuild would come back empty.
  v_count := public.close_month(v_air, v_month);
  if public.invoice_total(v_invoice) is distinct from round(1.4 * v_wet, 2) then
    raise exception 'FAIL  closing again rebuilt an issued invoice after restore';
  end if;

  -- The owners' rule travels with the schema: an admin does not record the
  -- payment that clears their own balance while there is another admin to ask.
  begin
    perform public.record_payment(v_admin, 100.00, public.aircraft_today());
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a restored admin cleared their own balance unwitnessed';
  end if;

  v_total := public.member_balance(v_pilot);
  if v_total <= 0 then
    raise exception 'FAIL  nothing is outstanding to pay after restore: %', v_total;
  end if;
  perform public.record_payment(v_pilot, v_total, public.aircraft_today(), 'restore check');

  if public.member_balance(v_pilot) is distinct from 0 then
    raise exception 'FAIL  paying in full left % after restore',
      public.member_balance(v_pilot);
  end if;
  select count(*) into v_count from public.invoice
   where member_id = v_pilot and status = 'issued';
  if v_count <> 0 then
    raise exception 'FAIL  % invoice(s) stayed due after the balance cleared', v_count;
  end if;

  -- And every one of those postings is still double entry, which is the whole
  -- reason the journal view exists.
  select coalesce(sum(debit_credit), 0) into v_max from public.gl_journal;
  if v_max <> 0 then
    raise exception 'FAIL  the restored journal nets to % once a month is closed', v_max;
  end if;

  raise notice 'PASS  a month closes, invoices, locks its flights and settles on vanilla Postgres';
end $$;
SQL

# Places are the one part of the schema written specifically to survive this
# script: the obvious implementation is PostGIS, and PostGIS is exactly what a
# stock image does not have. So the arithmetic, the matching and the journey
# wording are all plain SQL, and this is where that claim is checked.
echo "==> Checking places and the journey log"
psql_in <<'SQL'
do $$
declare
  v_company  uuid;
  v_air      uuid;
  v_pilot    uuid := '00000000-0000-0000-0000-0000000a00f0';
  v_narrows  uuid;
  v_lagoon   uuid;
  v_unused   uuid;
  v_landed   uuid;
  v_trip     uuid;
  v_circuit  uuid;
  v_typed    uuid;
  v_over     uuid;
  v_top      uuid;
  v_metres   numeric;
  v_radius   int;
  v_count    int;
  v_base     bigint;
  v_text     text;
  v_flag     boolean;
  v_blocked  text;
begin
  -- Without this the rest of the section proves nothing: if the throwaway had
  -- PostGIS, a distance_m that secretly depended on it would still work here
  -- and fail on the self-hosted box that does not.
  if exists (select 1 from pg_extension where extname = 'postgis') then
    raise exception 'FAIL  this check is vacuous: the throwaway image has PostGIS';
  end if;

  select c.id into v_company from public.company c limit 1;
  select a.id into v_air from public.aircraft a limit 1;

  -- places_used and place_times_used are deliberately scoped to the caller, so
  -- they need one. This is the roster row claimed near the top of the script.
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a00f1",
      "email":"restore-check@example.invalid"}', true);
  if public.current_member_id() is distinct from v_pilot then
    raise exception 'FAIL  the restore pilot could not be resolved for places';
  end if;

  -- A degree of latitude, which is a figure anyone can check against a chart:
  -- 111.2 km. Loose bounds on purpose -- the point is that haversine came back
  -- computing distances, not that it agrees to the metre.
  v_metres := public.distance_m(48.0, -123.0, 49.0, -123.0);
  if v_metres not between 111000 and 111400 then
    raise exception 'FAIL  a degree of latitude measured % m after restore', v_metres;
  end if;
  if public.distance_m(48.42, -123.39, 48.42, -123.39) is distinct from 0 then
    raise exception 'FAIL  a place is not where it is after restore';
  end if;

  -- Well away from the seeded places, so nothing but these rows can answer.
  insert into public.place (company_id, name, kind, lat, lon, created_by)
  values (v_company, 'Restore Narrows', 'dock', 50.000000, -125.000000, v_pilot)
  returning id into v_narrows;
  insert into public.place (company_id, name, kind, lat, lon, created_by)
  values (v_company, 'Restore Lagoon', 'bay', 50.100000, -125.100000, v_pilot)
  returning id into v_lagoon;
  insert into public.place (company_id, name, kind, lat, lon, created_by)
  values (v_company, 'Restore Shoal', 'other', 49.000000, -124.000000, v_pilot)
  returning id into v_unused;

  v_base := public.place_times_used(v_narrows);

  select a.place_match_radius_m into v_radius
  from public.aircraft a where a.id = v_air;
  if v_radius <> 1000 then
    raise exception 'FAIL  this check assumes a 1 km match radius, found % m', v_radius;
  end if;

  -- 556 m north of the dock: inside the kilometre, so the fix IS the dock.
  if public.place_match(v_air, 50.005, -125.0) is distinct from v_narrows then
    raise exception 'FAIL  a fix 556 m from a dock matched % after restore',
      public.place_match(v_air, 50.005, -125.0);
  end if;

  -- 1.7 km north: outside it, and nothing else is within 100 km, so null.
  if public.place_match(v_air, 50.015, -125.0) is not null then
    raise exception 'FAIL  a fix 1.7 km out still matched a dock after restore';
  end if;

  -- And the radius really is read off the aeroplane rather than hard-coded:
  -- widen it and the same fix matches. Varied both ways on purpose -- a radius
  -- only ever tested from one side proves nothing about where the line is.
  update public.aircraft set place_match_radius_m = 3000 where id = v_air;
  if public.place_match(v_air, 50.015, -125.0) is distinct from v_narrows then
    raise exception 'FAIL  widening the match radius matched nothing after restore';
  end if;
  update public.aircraft set place_match_radius_m = v_radius where id = v_air;

  raise notice 'PASS  distances and the match radius work without PostGIS';

  -- A stop fix names the landing place by itself, because the Shortcut writes
  -- fixes too and the rule has to live under both writers.
  insert into public.flight (aircraft_id, pilot_member_id, status, start_at, end_at)
  values (v_air, v_pilot, 'confirmed',
          now() - interval '3 hours', now() - interval '2 hours')
  returning id into v_landed;
  insert into public.flight_fix (flight_id, which, lat, lon, accuracy_m)
  values (v_landed, 'end', 50.004000, -125.000000, 9);

  select f.dest_place_id, f.landing_place_uncertain, f.journey_text
    into v_top, v_flag, v_text
  from public.flight f where f.id = v_landed;
  if v_top is distinct from v_narrows or v_flag then
    raise exception 'FAIL  a fix at the dock named % (uncertain: %) after restore',
      v_top, v_flag;
  end if;
  -- Half a journey is never stored; the origin here is still unknown.
  if v_text is not null then
    raise exception 'FAIL  a one-ended flight stored the journey "%" after restore', v_text;
  end if;

  -- And a stop nowhere known raises the flag instead of guessing.
  insert into public.flight (aircraft_id, pilot_member_id, status, start_at, end_at)
  values (v_air, v_pilot, 'confirmed',
          now() - interval '5 hours', now() - interval '4 hours')
  returning id into v_trip;
  insert into public.flight_fix (flight_id, which, lat, lon, accuracy_m)
  values (v_trip, 'end', 51.500000, -127.500000, 11);
  select f.dest_place_id is null and f.landing_place_uncertain into v_flag
  from public.flight f where f.id = v_trip;
  if not v_flag then
    raise exception 'FAIL  a stop 200 km from anywhere did not ask after restore';
  end if;

  -- Naming the landing place is what clears the flag, whoever named it.
  update public.flight set dest_place_id = v_lagoon where id = v_trip;
  select f.dest_place_id, f.landing_place_uncertain into v_top, v_flag
  from public.flight f where f.id = v_trip;
  if v_top is distinct from v_lagoon or v_flag then
    raise exception 'FAIL  naming a landing place left % (uncertain: %) after restore',
      v_top, v_flag;
  end if;

  -- And a fix never overrules a human. The fix below lands exactly on Restore
  -- Lagoon, so it HAS a match to impose -- which is the only way this proves
  -- anything. The pilot said the dock, so the dock it stays.
  insert into public.flight (aircraft_id, pilot_member_id, status, start_at, end_at,
                             dest_place_id)
  values (v_air, v_pilot, 'confirmed',
          now() - interval '11 hours', now() - interval '10 hours', v_narrows)
  returning id into v_over;
  insert into public.flight_fix (flight_id, which, lat, lon, accuracy_m)
  values (v_over, 'end', 50.100000, -125.100000, 7);
  select f.dest_place_id into v_top from public.flight f where f.id = v_over;
  if v_top is distinct from v_narrows then
    raise exception 'FAIL  a fix overwrote the place a human named, with % after restore',
      v_top;
  end if;

  raise notice 'PASS  a GPS fix names the landing place, or asks, on vanilla Postgres';

  -- The journey log line: derived from the two ends until somebody types one.
  update public.flight set origin_place_id = v_narrows where id = v_trip;
  select f.journey_text into v_text from public.flight f where f.id = v_trip;
  if v_text is distinct from 'Restore Narrows → Restore Lagoon' then
    raise exception 'FAIL  the derived journey restored as "%"', v_text;
  end if;

  insert into public.flight (aircraft_id, pilot_member_id, status, start_at, end_at,
                             origin_place_id, dest_place_id)
  values (v_air, v_pilot, 'confirmed',
          now() - interval '7 hours', now() - interval '6 hours',
          v_narrows, v_narrows)
  returning id into v_circuit;
  select f.journey_text into v_text from public.flight f where f.id = v_circuit;
  if v_text is distinct from 'Restore Narrows → local' then
    raise exception 'FAIL  a circuit restored as "%"', v_text;
  end if;

  insert into public.flight (aircraft_id, pilot_member_id, status, start_at, end_at,
                             origin_place_id, dest_place_id, journey_text)
  values (v_air, v_pilot, 'confirmed',
          now() - interval '9 hours', now() - interval '8 hours',
          v_narrows, v_lagoon, 'Up the inlet for lunch')
  returning id into v_typed;

  -- The rename that the saved-places manager exists for. It must correct every
  -- sentence this code wrote -- including the co-owner's, which is why the
  -- trigger is security definer -- and leave the typed one alone.
  update public.place set name = 'Restore Narrows dock' where id = v_narrows;

  select f.journey_text into v_text from public.flight f where f.id = v_trip;
  if v_text is distinct from 'Restore Narrows dock → Restore Lagoon' then
    raise exception 'FAIL  a rename left the derived journey as "%"', v_text;
  end if;
  select f.journey_text into v_text from public.flight f where f.id = v_circuit;
  if v_text is distinct from 'Restore Narrows dock → local' then
    raise exception 'FAIL  a rename left the circuit as "%"', v_text;
  end if;
  select f.journey_text into v_text from public.flight f where f.id = v_typed;
  if v_text is distinct from 'Up the inlet for lunch' then
    raise exception 'FAIL  a rename rewrote a pilot''s own journey as "%"', v_text;
  end if;

  -- Clearing the field is how a pilot asks for the derived sentence back.
  update public.flight set journey_text = '   ' where id = v_typed;
  select f.journey_text into v_text from public.flight f where f.id = v_typed;
  if v_text is distinct from 'Restore Narrows dock → Restore Lagoon' then
    raise exception 'FAIL  clearing a typed journey restored as "%"', v_text;
  end if;

  raise notice 'PASS  journey text derives, survives typing and follows a rename after restore';

  -- Nearest first, and the caller's own usage counted. Deltas rather than
  -- totals: the timer check above already flew this member somewhere.
  select n.id into v_top from public.places_near(50.0, -125.0, 3) n limit 1;
  if v_top is distinct from v_narrows then
    raise exception 'FAIL  places_near put % first after restore', v_top;
  end if;
  if public.place_times_used(v_narrows) - v_base <> 5 then
    raise exception 'FAIL  the dock counts % flights after restore, expected %',
      public.place_times_used(v_narrows), v_base + 5;
  end if;
  select u.id into v_top from public.places_used(6) u limit 1;
  if v_top is distinct from v_narrows then
    raise exception 'FAIL  places_used put % first after restore', v_top;
  end if;

  -- Deleting a place a flight names would quietly empty that flight's origin,
  -- because the foreign keys are ON DELETE SET NULL. An unused one is fine.
  begin
    delete from public.place where id = v_narrows;
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  select count(*) into v_count from public.place where id = v_narrows;
  if v_blocked is null or v_count <> 1 then
    raise exception 'FAIL  a place on 5 flights was deleted after restore';
  end if;

  delete from public.place where id = v_unused;
  select count(*) into v_count from public.place where id = v_unused;
  if v_count <> 0 then
    raise exception 'FAIL  an unused place could not be deleted after restore';
  end if;

  raise notice 'PASS  a place in use is protected and an unused one is not, on vanilla Postgres';
end $$;
SQL

# The chores are the piece that reminds an admin to reconcile the bank, and the
# reminder is only worth anything if it arrives at the right person. All of
# that is triggers, a security definer function and a PARTIAL unique index --
# three things a dump can plausibly lose while still restoring "cleanly" -- so
# it is checked on the throwaway rather than only locally.
echo "==> Checking tasks and the rotation"
psql_in <<'SQL'
do $$
declare
  v_company  uuid;
  v_air      uuid;
  v_admin    uuid := '00000000-0000-0000-0000-0000000a00fa';
  v_pilot    uuid := '00000000-0000-0000-0000-0000000a00f0';
  v_series   uuid;
  v_shared   uuid;
  v_task     uuid;
  v_next     uuid;
  v_first    uuid;
  v_asgn     uuid;
  v_done     uuid;
  v_after_done uuid;
  v_after_asgn uuid;
  v_month    date;
  v_count    int;
  v_made     int;
  v_due      date;
  v_blocked  text;
begin
  select c.id into v_company from public.company c limit 1;
  select a.id into v_air from public.aircraft a limit 1;

  -- The stamp trigger attributes a finished chore to whoever is signed in, and
  -- close_month refuses a non-admin, so this section needs a caller and it has
  -- to be the admin claimed earlier in the script. Read the auth id back off
  -- the row rather than restating it, so this cannot drift from the claim.
  perform set_config('request.jwt.claims',
    json_build_object(
      'sub',   (select m.auth_user_id from public.member m where m.id = v_admin),
      'email', 'restore-admin@example.invalid')::text, true);

  if public.current_member_id() is distinct from v_admin then
    raise exception 'FAIL  the restore admin could not be resolved for tasks';
  end if;
  if not public.is_admin() then
    raise exception 'FAIL  the restore admin does not read as an admin';
  end if;

  -- ---------------------------------------------------------------------
  -- Whose turn
  -- ---------------------------------------------------------------------

  insert into public.task_series (company_id, title, recurrence, interval_days,
                                  admins_only)
  values (v_company, 'Restore float wash', 'interval_days', 90, true)
  returning id into v_series;

  -- Read who is actually at the top rather than naming them: the roster here
  -- is whatever the export happened to contain plus the two rows this script
  -- made, so a hard-coded name would be an assertion about the seed.
  select r.member_id into v_first
  from public.task_rotation(v_series) r order by r.turn limit 1;

  select count(*) into v_count from public.task_rotation(v_series)
   where member_id = v_pilot;
  if v_count <> 0 then
    raise exception 'FAIL  a pilot is in the rotation for an admins-only chore after restore';
  end if;

  -- Varied the other way, or "excluded" could just mean the rotation never had
  -- anyone but the admins in it to begin with.
  insert into public.task_series (company_id, title, recurrence, interval_days,
                                  admins_only)
  values (v_company, 'Restore shared chore', 'interval_days', 30, false)
  returning id into v_shared;

  select count(*) into v_count from public.task_rotation(v_shared)
   where member_id = v_pilot;
  if v_count <> 1 then
    raise exception 'FAIL  a pilot is excluded from a chore that is not admins-only';
  end if;

  raise notice 'PASS  the rotation is the active roster, and admin chores stay with admins, on vanilla Postgres';

  -- ---------------------------------------------------------------------
  -- The turn advances from whoever did the work
  -- ---------------------------------------------------------------------

  insert into public.task (company_id, series_id, title, assignee_member_id,
                           due_date)
  values (v_company, v_series, 'Restore float wash',
          public.task_next_assignee(v_series),
          public.aircraft_today() - 14)
  returning id into v_task;

  if (select t.assignee_member_id from public.task t where t.id = v_task)
     is distinct from v_first then
    raise exception 'FAIL  the first turn did not go to the top of the rotation';
  end if;

  -- Hand it to somebody else and then do it anyway, which is the ordinary thing
  -- that happens between two owners -- and the only arrangement under which
  -- "advances from the completer" and "advances from the assignee" are
  -- different sentences. Which of them the caller happens to sort next to is
  -- not something this script can choose, so it is read, not assumed.
  select r.member_id into v_asgn
  from public.task_rotation(v_series) r
  where r.member_id <> v_admin
  order by r.turn limit 1;

  if v_asgn is null then
    raise exception 'FAIL  this check is vacuous: the rotation holds nobody but the caller';
  end if;

  update public.task set assignee_member_id = v_asgn where id = v_task;
  update public.task set status = 'done' where id = v_task;

  select t.completed_by into v_done from public.task t where t.id = v_task;

  if v_done is distinct from v_admin then
    raise exception 'FAIL  the restored stamp credits % and not the caller', v_done;
  end if;

  -- Exactly one successor, 90 days from when it was really done rather than
  -- from when it was meant to be -- it was deliberately set a fortnight late.
  select count(*) into v_count from public.task
   where series_id = v_series and status = 'open';
  if v_count <> 1 then
    raise exception 'FAIL  ticking a recurring chore left % successors after restore',
      v_count;
  end if;

  select t.due_date, t.assignee_member_id into v_due, v_next
  from public.task t where t.series_id = v_series and t.status = 'open';

  if v_due <> public.aircraft_today() + 90 then
    raise exception 'FAIL  the restored successor is due %, not 90 days from today',
      v_due;
  end if;

  -- Work out both answers and insist they differ before picking between them,
  -- otherwise the comparison below proves nothing.
  select r.member_id into v_after_done
  from public.task_rotation(v_series) r
  where r.turn > (select r2.turn from public.task_rotation(v_series) r2
                   where r2.member_id = v_done)
  order by r.turn limit 1;

  select r.member_id into v_after_asgn
  from public.task_rotation(v_series) r
  where r.turn > (select r2.turn from public.task_rotation(v_series) r2
                   where r2.member_id = v_asgn)
  order by r.turn limit 1;

  if v_after_done is not distinct from v_after_asgn then
    raise exception 'FAIL  this check is vacuous: both rules name the same member';
  end if;

  if v_next is distinct from v_after_done then
    raise exception 'FAIL  the turn went to % -- the member after the assignee, not after the completer',
      v_next;
  end if;

  raise notice 'PASS  a finished chore is stamped and hands the turn on, on vanilla Postgres';

  -- ---------------------------------------------------------------------
  -- The chore that closing a month creates
  -- ---------------------------------------------------------------------

  -- Two months back, so this cannot disturb the invoice assertions earlier in
  -- the script, and far enough from today that it is certainly not in future.
  v_month := date_trunc('month', public.aircraft_today() - interval '2 months')::date;

  insert into public.task_series (company_id, title, recurrence,
                                  due_offset_days)
  values (v_company, 'Restore reconcile', 'month_close', 10)
  returning id into v_series;

  perform public.close_month(v_air, v_month);

  select count(*) into v_count from public.task
   where series_id = v_series and period_month = v_month;
  if v_count <> 1 then
    raise exception 'FAIL  closing a month after restore created % chores, not 1',
      v_count;
  end if;

  select t.id, t.due_date into v_task, v_due from public.task t
   where t.series_id = v_series and t.period_month = v_month;

  if v_due <> (v_month + interval '1 month - 1 day')::date + 10 then
    raise exception 'FAIL  the restored reconcile chore is due %, not ten days after the month end',
      v_due;
  end if;

  -- close_month is re-runnable by design, and the partial unique index is half
  -- of why that is safe. If the dump lost the index, the not-exists guard would
  -- still make this pass -- so the index is asserted to exist by name as well.
  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'task_series_period_idx'
  ) then
    raise exception 'FAIL  the partial unique index on (series_id, period_month) did not restore';
  end if;

  perform public.close_month(v_air, v_month);

  select count(*) into v_count from public.task
   where series_id = v_series and period_month = v_month;
  if v_count <> 1 then
    raise exception 'FAIL  re-closing the month after restore left % chores', v_count;
  end if;

  -- And a chore already done is not handed back by the next close.
  update public.task set status = 'done' where id = v_task;
  perform public.close_month(v_air, v_month);

  select count(*) into v_count from public.task
   where series_id = v_series and period_month = v_month and status = 'open';
  if v_count <> 0 then
    raise exception 'FAIL  re-closing resurrected a reconcile chore already done';
  end if;

  -- The index is doing real work, not merely present: an insert that evades the
  -- guard must still be refused.
  begin
    insert into public.task (company_id, series_id, period_month, title,
                             due_date)
    values (v_company, v_series, v_month, 'Duplicate reconcile', v_due);
  exception when others then
    v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a second chore for the same month and series was accepted';
  end if;

  -- A different month is a different chore, which is the other half of it.
  v_made := public.task_spawn_for_month(
    v_company, (v_month + interval '1 month')::date);
  if v_made < 1 then
    raise exception 'FAIL  the following month got no reconcile chore';
  end if;
  select count(*) into v_count from public.task
   where series_id = v_series
     and period_month = (v_month + interval '1 month')::date;
  if v_count <> 1 then
    raise exception 'FAIL  the following month got % chores on this series, not 1',
      v_count;
  end if;

  raise notice 'PASS  closing a month creates its reconcile chore exactly once, on vanilla Postgres';
end $$;
SQL

# Receipts are the one phase with a foot outside Postgres, so this is where the
# line between the two halves gets tested.
#
# The IMAGES are in Supabase Storage, and nothing about that travels in this
# dump -- the bucket and its policies live in the `storage` schema, which
# export-db.sh does not take. That is the design, not an omission: the images
# come out as a directory of files alongside the dump, and lib/storage.ts is
# rewritten to address wherever they land.
#
# Everything that decides what a receipt MEANS is in `public`, so it is in the
# dump and it has to work here: who may agree to one, that it cannot be agreed
# without its picture, that agreeing freezes it, and that agreeing is what turns
# it into money off that member's bill. Including receipt_is_locked(), which the
# bucket policies call -- the policies do not travel, but the predicate they are
# built out of does, and a self-hosted store needs it just the same.
echo "==> Checking receipts and approvals"
psql_in <<'SQL'
do $$
declare
  v_company  uuid;
  v_air      uuid;
  v_admin    uuid := '00000000-0000-0000-0000-0000000a00fa';
  v_pilot    uuid := '00000000-0000-0000-0000-0000000a00f0';
  v_account  text;
  v_expense  uuid;
  v_month    date;
  v_spent    date;
  v_key      text;
  v_amount   numeric;
  v_gst      numeric;
  v_invoice  uuid;
  v_count    int;
  v_blocked  text;
  v_reviewer uuid;
begin
  select c.id into v_company from public.company c limit 1;
  select a.id into v_air from public.aircraft a limit 1;

  -- An expense account for this company, read off the restored chart rather
  -- than named: which codes a company uses is its own business, and the point
  -- being made here is that the TYPE is what the schema cares about.
  select g.code into v_account from public.gl_account g
   where g.company_id = v_company and g.type = 'expense' order by g.code limit 1;
  if v_account is null then
    raise exception 'FAIL  the restored chart of accounts has nothing to spend on';
  end if;

  -- The fuel was bought three months ago; the bill it has to land on is the
  -- current month, because that is the first one still open when the other
  -- owner finally gets round to agreeing it. Both derived, because a literal
  -- month here would expire.
  v_spent := date_trunc('month', public.aircraft_today() - interval '3 months')::date + 12;
  v_month := date_trunc('month', public.aircraft_today())::date;
  if public.month_is_closed(v_company, v_month) then
    raise exception 'FAIL  % is already billed, so nothing here can be tested', v_month;
  end if;

  -- ---------------------------------------------------------------------
  -- Who may agree to it
  -- ---------------------------------------------------------------------

  -- The pilot is in session and the pilot is the one being reimbursed, which
  -- is the case the whole approval step exists for.
  perform set_config('request.jwt.claims',
    json_build_object(
      'sub',   (select m.auth_user_id from public.member m where m.id = v_pilot),
      'email', 'restore-pilot@example.invalid')::text, true);
  if public.current_member_id() is distinct from v_pilot then
    raise exception 'FAIL  the restore pilot could not be resolved for receipts';
  end if;

  v_key := 'receipt/' || v_company || '/1999/01/' || gen_random_uuid() || '.jpg';

  insert into public.expense (
    company_id, aircraft_id, payer, paid_by_member_id, vendor, spent_on,
    total_amount, gl_account_code, litres, status
  ) values (
    v_company, v_air, 'member', v_pilot, 'Restore Fuel Dock', v_spent,
    120.00, v_account, 60.00, 'submitted'
  ) returning id into v_expense;

  if public.receipt_is_locked(v_key) then
    raise exception 'FAIL  a key with nothing approved against it restored locked';
  end if;

  begin
    update public.expense set status = 'approved', receipt_key = v_key
     where id = v_expense;
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a restored owner approved the receipt that pays them';
  end if;

  -- Somebody else, and only with the picture.
  perform set_config('request.jwt.claims',
    json_build_object(
      'sub',   (select m.auth_user_id from public.member m where m.id = v_admin),
      'email', 'restore-admin@example.invalid')::text, true);
  if public.current_member_id() is distinct from v_admin then
    raise exception 'FAIL  the restore admin could not be resolved for receipts';
  end if;

  begin
    update public.expense set status = 'approved' where id = v_expense;
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a restored receipt was agreed with no image attached';
  end if;

  update public.expense set receipt_key = v_key, status = 'approved'
   where id = v_expense;

  select e.reviewed_by into v_reviewer from public.expense e where e.id = v_expense;
  if v_reviewer is distinct from v_admin then
    raise exception 'FAIL  the restored receipt records % as the approver', v_reviewer;
  end if;

  if not public.receipt_is_locked(v_key) then
    raise exception 'FAIL  an approved receipt image restored still replaceable';
  end if;

  begin
    update public.expense set total_amount = 1.00 where id = v_expense;
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  an approved receipt was re-priced after restore';
  end if;

  raise notice 'PASS  a receipt needs somebody else and its picture, then freezes, on vanilla Postgres';

  -- ---------------------------------------------------------------------
  -- What agreeing to it does to the bill
  -- ---------------------------------------------------------------------

  -- Note what has just happened to the dates: the fuel was bought three months
  -- ago and agreed a moment ago. A restore that brought across a narrower rule
  -- -- "receipts bought during the month" -- would strand this one behind a
  -- bill that has already gone out, which is the failure nobody notices until
  -- an owner says they were never paid back.
  select c.amount, c.gst_amount into v_amount, v_gst
    from public.month_charges(v_air, v_pilot, v_month) c
   where c.kind = 'expense_credit'
     and c.description like '%Restore Fuel Dock%';

  if v_amount is null then
    raise exception 'FAIL  an approved receipt produced no credit after restore';
  end if;
  -- Whole, and the opposite sign from a charge: the member is owed it.
  if v_amount + v_gst <> -120.00 then
    raise exception 'FAIL  the restored credit is % + % gst, not -120.00 in total',
      v_amount, v_gst;
  end if;

  -- ... and it is not also sitting on the month it was bought in, which nobody
  -- had agreed it in yet.
  if exists (
    select 1 from public.month_charges(
      v_air, v_pilot, date_trunc('month', v_spent)::date) c
     where c.kind = 'expense_credit'
       and c.description like '%Restore Fuel Dock%'
  ) then
    raise exception 'FAIL  the credit was backdated to % after restore',
      date_trunc('month', v_spent)::date;
  end if;

  -- Bill it.
  v_count := public.close_month(v_air, v_month);
  if v_count = 0 then
    raise exception 'FAIL  a month containing only a receipt credit built no drafts';
  end if;

  select i.id into v_invoice from public.invoice i
   where i.member_id = v_pilot and i.period_month = v_month;
  if v_invoice is null then
    raise exception 'FAIL  the member who bought the fuel got no draft after restore';
  end if;
  -- The credit is ON that invoice, as its own line. Not asserted against the
  -- invoice total, which also carries whatever this pilot flew: a figure like
  -- that is really an assertion about the fixture and breaks the next time the
  -- fixture gains a flight.
  select coalesce(sum(l.amount + l.gst_amount), 0) into v_amount
    from public.ledger_entry l
   where l.invoice_id = v_invoice and l.kind = 'expense_credit';
  if v_amount <> -120.00 then
    raise exception 'FAIL  the invoice carries % of receipt credit, not -120.00',
      v_amount;
  end if;

  perform public.issue_invoice(v_invoice);

  -- The lock, the same one flights get: the receipt that was priced is now on
  -- the invoice that priced it, so next month cannot credit it again.
  if (select e.invoice_id from public.expense e where e.id = v_expense)
     is distinct from v_invoice then
    raise exception 'FAIL  issuing left the restored receipt unattached';
  end if;

  select count(*) into v_count
    from public.month_charges(
      v_air, v_pilot, (v_month + interval '1 month')::date) c
   where c.kind = 'expense_credit'
     and c.description like '%Restore Fuel Dock%';
  if v_count <> 0 then
    raise exception 'FAIL  a billed receipt was credited again next month after restore';
  end if;

  -- And the postings still net, with a credit in among them.
  if (select coalesce(sum(debit_credit), 0) from public.gl_journal) <> 0 then
    raise exception 'FAIL  the restored journal stopped balancing once a receipt was credited';
  end if;

  raise notice 'PASS  an agreed receipt is credited once and attached to its invoice on vanilla Postgres';
end $$;
SQL

echo "==> Checking the aeroplane's running log"
psql_in <<'SQL'
do $$
declare
  v_air    uuid;
  v_member uuid;
  v_note   uuid;
  v_flight uuid;
  v_day    date;
  v_read   numeric;
  v_est    numeric;
  v_count  int;
begin
  select a.id into v_air from public.aircraft a limit 1;
  select m.id into v_member from public.member m where m.is_active order by m.full_name limit 1;

  if public.aircraft_tach_estimate(v_air) is null then
    raise exception 'FAIL  the restored aeroplane has no tach reading to measure from';
  end if;

  -- A day after everything this script has already done. The sections above
  -- leave a reading dated a day ahead to prove that a fresh reading IS the
  -- reset, so "today" is not the end of this aeroplane's history and a note
  -- written today would not be the newest thing on it. Derived rather than
  -- guessed, so reordering the sections above cannot quietly make this one
  -- vacuous.
  select greatest(
           coalesce(max(public.aircraft_date(r.read_at)), public.aircraft_today()),
           coalesce((select max(public.aircraft_date(f.start_at))
                       from public.flight f where f.aircraft_id = v_air),
                    public.aircraft_today())
         ) + 1
    into v_day
    from public.tach_reading r
   where r.aircraft_id = v_air;

  -- A flight that morning, so there is something for a midnight-stamped
  -- reading to double-count. Written with the restored aircraft_today() and
  -- zone, because the zone travelling is half of what is being tested: a
  -- vanilla Postgres whose own clock is UTC must still agree about what day it
  -- is in Victoria.
  insert into public.flight
    (aircraft_id, pilot_member_id, status, start_at, end_at, tach_factor_used)
  values
    (v_air, v_member, 'confirmed',
     (v_day + time '09:00') at time zone 'America/Vancouver',
     (v_day + time '10:00') at time zone 'America/Vancouver',
     1.300)
  returning id into v_flight;

  if (select f.est_tach_hours from public.flight f where f.id = v_flight) is null
     or (select f.est_tach_hours from public.flight f where f.id = v_flight) <= 0 then
    raise exception 'FAIL  the morning flight has no hours to be counted twice';
  end if;

  v_read := round(public.aircraft_tach_estimate(v_air) + 5, 2);

  insert into public.aircraft_note (aircraft_id, body, noted_on, noted_by, tach)
  values (v_air, 'Added a qt of oil after the restore', v_day, v_member, v_read)
  returning id into v_note;

  -- The trigger came across, so the note still moves the maintenance clock.
  select count(*) into v_count from public.tach_reading where note_id = v_note;
  if v_count <> 1 then
    raise exception 'FAIL  a note''s tach was not mirrored after restore (% rows)', v_count;
  end if;

  v_est := public.aircraft_tach_estimate(v_air);
  if v_est is distinct from v_read then
    raise exception
      'FAIL  the restored estimate is % but the meter was read at % -- this morning was counted twice',
      v_est, v_read;
  end if;

  -- And the cascade came across. Asked as "is the number gone", not "does
  -- anything still point at the note": a link that nulled instead of cascading
  -- would leave the reading setting every due-date, and counting by note_id
  -- would read zero either way.
  delete from public.aircraft_note where id = v_note;
  select count(*) into v_count
    from public.tach_reading where aircraft_id = v_air and reading = v_read;
  if v_count <> 0 then
    raise exception 'FAIL  a deleted note left its reading behind after restore';
  end if;
  if public.aircraft_tach_estimate(v_air) >= v_read then
    raise exception 'FAIL  a deleted note still sets the restored tach estimate';
  end if;

  delete from public.flight where id = v_flight;

  raise notice 'PASS  a log note moves the tach and lets go of it again on vanilla Postgres';
end $$;
SQL

# The one thing in the schema that depends on an extension, so the one most
# likely to be lost in a move. --schema=public does NOT carry btree_gist on its
# own: without --extension in export-db.sh the restore dies on this constraint
# with "data type uuid has no default operator class for access method gist",
# and a restore that got no further would at least be loud. The quieter failure
# this section is really here for is a dump that rebuilt the TABLE but dropped
# the CONSTRAINT -- the calendar would restore looking perfect and silently
# start accepting double-bookings.
echo "==> Checking the booking calendar"
psql_in <<'SQL'
do $$
declare
  v_air     uuid;
  v_one     uuid;
  v_two     uuid;
  v_day     date;
  v_blocked text;
  v_count   int;
begin
  select a.id into v_air from public.aircraft a limit 1;
  select m.id into v_one from public.member m where m.is_active order by m.full_name limit 1;
  select m.id into v_two from public.member m
   where m.is_active and m.id <> v_one order by m.full_name limit 1;
  if v_two is null then
    raise exception 'FAIL  VACUOUS: one owner cannot double-book anybody';
  end if;

  -- Far enough out that the seeded bookings cannot be what is being measured.
  v_day := public.aircraft_today() + 300;

  insert into public.booking (aircraft_id, pilot_member_id, start_at, end_at)
  values (v_air, v_one,
          (v_day + time '09:00') at time zone 'America/Vancouver',
          (v_day + time '12:00') at time zone 'America/Vancouver');

  -- A handover at noon is NOT a clash. Asserting this before the refusal
  -- matters: a constraint built with a closed range would still refuse the
  -- overlap below, so the refusal alone cannot tell the two apart -- and the
  -- version that forbids this is the one owners would notice first.
  insert into public.booking (aircraft_id, pilot_member_id, start_at, end_at)
  values (v_air, v_two,
          (v_day + time '12:00') at time zone 'America/Vancouver',
          (v_day + time '17:00') at time zone 'America/Vancouver');

  -- And one minute into somebody else's slot is.
  begin
    insert into public.booking (aircraft_id, pilot_member_id, start_at, end_at)
    values (v_air, v_two,
            (v_day + time '11:59') at time zone 'America/Vancouver',
            (v_day + time '13:00') at time zone 'America/Vancouver');
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  the restored calendar accepted a double-booking';
  end if;

  select count(*) into v_count from public.booking
   where aircraft_id = v_air and public.aircraft_date(start_at) = v_day;
  if v_count <> 2 then
    raise exception 'FAIL  expected 2 bookings that day after restore, found %', v_count;
  end if;

  delete from public.booking
   where aircraft_id = v_air and public.aircraft_date(start_at) = v_day;

  raise notice 'PASS  the aeroplane cannot be in two places at once on vanilla Postgres';
end $$;
SQL

# A STATEMENT-level trigger, which is the kind a dump is most likely to leave
# behind: nothing references it, no column mentions it, and the roster restores
# looking perfect without it. What is lost is the one rule standing between an
# admin and locking every owner out of their own aeroplane, and it would not be
# noticed until the day somebody pressed the button.
echo "==> Checking that the roster still keeps an admin"
psql_in <<'SQL'
begin;

-- There is no auth.uid() in a restored database, so is_admin() is false and
-- member_guard_privileged_columns refuses every one of these changes before
-- the rule under test gets a say -- which would make this section pass without
-- proving anything. That guard is checked in verify-rls.sql, where there is a
-- signed-in admin to check it against. Standing it down here is DDL, so the
-- rollback at the end puts it back along with the rest.
alter table public.member disable trigger member_guard_privileged_columns;

do $$
declare
  v_solo    uuid;
  v_blocked text;
  v_role    text;
  v_admins  int;
begin
  -- A member of this restored roster, not a seeded id: the point is the rule,
  -- and the rule has to hold for whoever is actually in the dump.
  insert into public.member (full_name, email, role)
  values ('Restore Guard Admin', 'restoreguard@example.test', 'admin')
  returning id into v_solo;

  -- Make this the only active admin, so the next change is the last-admin case.
  update public.member set role = 'pilot'
   where role = 'admin' and id <> v_solo;

  select count(*) into v_admins
  from public.member where is_active and role = 'admin';
  if v_admins <> 1 then
    raise exception 'SETUP  expected one admin after restore, found %', v_admins;
  end if;

  begin
    update public.member set role = 'pilot' where id = v_solo;
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  the restored roster let its last admin step down';
  end if;

  begin
    update public.member set is_active = false where id = v_solo;
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  the restored roster let its last admin be retired';
  end if;

  -- And the rule is the last-admin one, not a blanket refusal: with somebody
  -- else promoted, the same demotion goes through.
  update public.member set role = 'admin'
   where id = (select id from public.member
                where is_active and id <> v_solo order by full_name limit 1);
  update public.member set role = 'pilot' where id = v_solo;

  select m.role::text into v_role from public.member m where m.id = v_solo;
  if v_role <> 'pilot' then
    raise exception 'FAIL  a handover was refused on the restored roster';
  end if;

  raise notice 'PASS  the roster keeps an admin, and a handover still works, on vanilla Postgres';
end $$;

rollback;
SQL

echo
echo "Escape hatch verified: the export restores and runs on vanilla PostgreSQL."
