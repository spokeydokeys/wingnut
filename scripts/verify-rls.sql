-- Security and invariant checks for the core schema.
--
-- Run against the local stack:
--   psql "$(npx supabase status -o env | grep DB_URL | cut -d= -f2- | tr -d '\"')" \
--        -f scripts/verify-rls.sql
--
-- Every test runs in its own transaction and rolls back, so this never mutates
-- seed data. Any FAIL raises and aborts. RLS is exercised by setting
-- request.jwt.claims, which is what auth.uid() reads, rather than by creating
-- real auth users.

\set ON_ERROR_STOP on

-- ===========================================================================
-- 1. Ownership shares in a period must account for exactly 100%.
-- ===========================================================================
begin;
do $$
declare
  v_ok boolean := false;
begin
  begin
    insert into public.ownership_period (id, aircraft_id, effective_from)
    values ('00000000-0000-0000-0000-0000000dead1',
            '00000000-0000-0000-0000-0000000ac001',
            date '2027-01-01');

    insert into public.ownership_share (period_id, member_id, pct)
    values ('00000000-0000-0000-0000-0000000dead1',
            '00000000-0000-0000-0000-00000000a001',
            60);

    -- The invariant trigger is deferred, so force it to fire now.
    set constraints all immediate;
  exception when others then
    v_ok := true;
  end;

  if not v_ok then
    raise exception 'FAIL  a period summing to 60%% was accepted';
  end if;
  raise notice 'PASS  ownership shares must sum to 100';
end $$;
rollback;

-- ===========================================================================
-- 2. Effective-dated ownership: adding owners must not rewrite past months.
--    This is the invariant the whole period model exists to protect.
-- ===========================================================================
begin;

insert into public.member (id, full_name, email) values
  ('00000000-0000-0000-0000-00000000a003', 'Test Three', 't3@example.test'),
  ('00000000-0000-0000-0000-00000000a004', 'Test Four',  't4@example.test');

insert into public.ownership_period (id, aircraft_id, effective_from, note)
values ('00000000-0000-0000-0000-0000000dead2',
        '00000000-0000-0000-0000-0000000ac001',
        date '2026-07-01',
        'Two more owners join');

insert into public.ownership_share (period_id, member_id, pct) values
  ('00000000-0000-0000-0000-0000000dead2', '00000000-0000-0000-0000-00000000a001', 25),
  ('00000000-0000-0000-0000-0000000dead2', '00000000-0000-0000-0000-00000000a002', 25),
  ('00000000-0000-0000-0000-0000000dead2', '00000000-0000-0000-0000-00000000a003', 25),
  ('00000000-0000-0000-0000-0000000dead2', '00000000-0000-0000-0000-00000000a004', 25);

set constraints all immediate;

do $$
declare
  v_count int;
  v_max   numeric;
begin
  select count(*), max(pct) into v_count, v_max
  from public.ownership_as_of('00000000-0000-0000-0000-0000000ac001', date '2026-06-30');
  if v_count <> 2 or v_max <> 50 then
    raise exception 'FAIL  June resolved to % owners, max %%%', v_count, v_max;
  end if;
  raise notice 'PASS  a month before the change keeps the old 50/50 split';

  select count(*), max(pct) into v_count, v_max
  from public.ownership_as_of('00000000-0000-0000-0000-0000000ac001', date '2026-07-01');
  if v_count <> 4 or v_max <> 25 then
    raise exception 'FAIL  July resolved to % owners, max %%%', v_count, v_max;
  end if;
  raise notice 'PASS  new owners apply from their effective date forward';
end $$;
rollback;

-- ===========================================================================
-- 3. A pilot must not be able to promote themselves to admin.
-- ===========================================================================
begin;

insert into public.member (id, auth_user_id, full_name, email, role)
values ('00000000-0000-0000-0000-00000000a005',
        '00000000-0000-0000-0000-0000000a0005',
        'Test Pilot', 'pilot@example.test', 'pilot');

do $$
declare
  v_ok boolean := false;
begin
  begin
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims',
                       '{"sub":"00000000-0000-0000-0000-0000000a0005"}', true);

    update public.member
       set role = 'admin'
     where id = '00000000-0000-0000-0000-00000000a005';
  exception when others then
    v_ok := true;
  end;

  perform set_config('role', 'postgres', true);

  if not v_ok then
    raise exception 'FAIL  a pilot promoted themselves to admin';
  end if;
  raise notice 'PASS  a pilot cannot promote themselves to admin';
end $$;
rollback;

-- ===========================================================================
-- 4. A pilot must not be able to change shared aircraft configuration.
--    The tach factor drives every tach estimate, so it is admin-only.
-- ===========================================================================
begin;

insert into public.member (id, auth_user_id, full_name, email, role)
values ('00000000-0000-0000-0000-00000000a006',
        '00000000-0000-0000-0000-0000000a0006',
        'Test Pilot Two', 'pilot2@example.test', 'pilot');

do $$
declare
  v_rows int;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
                     '{"sub":"00000000-0000-0000-0000-0000000a0006"}', true);

  update public.aircraft
     set tach_factor = 9.999
   where id = '00000000-0000-0000-0000-0000000ac001';
  get diagnostics v_rows = row_count;

  perform set_config('role', 'postgres', true);

  -- RLS filters the row out rather than raising, so assert nothing changed.
  if v_rows <> 0 then
    raise exception 'FAIL  a pilot updated % aircraft row(s)', v_rows;
  end if;
  raise notice 'PASS  a pilot cannot change aircraft configuration';
end $$;
rollback;

-- ===========================================================================
-- 5. The anon role must reach nothing.
-- ===========================================================================
begin;
do $$
declare
  v_ok    boolean := false;
  v_count int;
begin
  begin
    perform set_config('role', 'anon', true);
    select count(*) into v_count from public.member;
    -- Reaching here without an error is only acceptable if no rows came back.
    if v_count = 0 then
      v_ok := true;
    end if;
  exception when insufficient_privilege then
    v_ok := true;
  end;

  perform set_config('role', 'postgres', true);

  if not v_ok then
    raise exception 'FAIL  anon read % member row(s)', v_count;
  end if;
  raise notice 'PASS  anon cannot read members';
end $$;
rollback;

-- ===========================================================================
-- 6. An active member can read the roster (needed for bookings and approvals).
-- ===========================================================================
begin;
do $$
declare
  v_count int;
begin
  -- The seed leaves the roster unclaimed, so sign in the way the app does.
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a0001",
      "email":"owner1@example.test"}', true);
  perform public.claim_member_identity();

  select count(*) into v_count from public.member;

  perform set_config('role', 'postgres', true);

  if v_count < 2 then
    raise exception 'FAIL  an owner could only see % member row(s)', v_count;
  end if;
  raise notice 'PASS  an owner can read the member roster';
end $$;
rollback;

-- ===========================================================================
-- 7. First sign-in claims the roster row matching the verified email, and an
--    email that is not on the roster claims nothing.
-- ===========================================================================
begin;
do $$
declare
  v_member uuid;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a0007",
      "email":"Owner1@Example.test"}', true);

  -- Case matches loosely: member.email is stored as typed, the claim is not.
  v_member := public.claim_member_identity();
  if v_member <> '00000000-0000-0000-0000-00000000a001' then
    raise exception 'FAIL  claim returned % for a roster email', v_member;
  end if;

  -- Second call must be a no-op returning the same row.
  if public.claim_member_identity() <> v_member then
    raise exception 'FAIL  claim is not idempotent';
  end if;

  perform set_config('role', 'postgres', true);
  raise notice 'PASS  a roster email claims its member row, idempotently';
end $$;
rollback;

begin;
do $$
declare
  v_member uuid;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a0008",
      "email":"stranger@example.test"}', true);

  v_member := public.claim_member_identity();

  perform set_config('role', 'postgres', true);

  if v_member is not null then
    raise exception 'FAIL  an off-roster email claimed member %', v_member;
  end if;
  raise notice 'PASS  an authenticated stranger claims no member row';
end $$;
rollback;

-- ===========================================================================
-- 8. A member still cannot re-point an already-claimed row at themselves.
-- ===========================================================================
begin;
do $$
declare
  v_blocked text;
begin
  -- Fixture built only from legitimate paths: both members claim their own row,
  -- then the admin demotes the other one to pilot.
  perform set_config('role', 'authenticated', true);

  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a0009",
      "email":"owner2@example.test"}', true);
  perform public.claim_member_identity();

  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a0001",
      "email":"owner1@example.test"}', true);
  perform public.claim_member_identity();

  update public.member set role = 'pilot'
   where id = '00000000-0000-0000-0000-00000000a002';

  perform set_config('request.jwt.claims',
                     '{"sub":"00000000-0000-0000-0000-0000000a0009"}', true);

  -- The pilot's own row is the one RLS lets them update, so this is where the
  -- guard trigger has to do the work: re-pointing an already-claimed mapping.
  begin
    update public.member
       set auth_user_id = '00000000-0000-0000-0000-0000000a0001'
     where id = '00000000-0000-0000-0000-00000000a002';
    v_blocked := null;
  exception when others then
    v_blocked := sqlerrm;
  end;

  perform set_config('role', 'postgres', true);

  if v_blocked is null then
    raise exception 'FAIL  a pilot re-pointed their own claimed auth mapping';
  end if;
  if (select auth_user_id from public.member
       where id = '00000000-0000-0000-0000-00000000a002')
     <> '00000000-0000-0000-0000-0000000a0009' then
    raise exception 'FAIL  the auth mapping moved';
  end if;
  raise notice 'PASS  a claimed auth mapping cannot be re-pointed (%)', v_blocked;
end $$;
rollback;

\echo ''
\echo 'All core schema checks passed.'
