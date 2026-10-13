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
--
-- Several tests sign a member in by calling claim_member_identity(), which only
-- claims an UNCLAIMED row -- so they need the roster unclaimed, and a database
-- that has ever been signed into from a browser does not have one. Those tests
-- start by releasing the mapping with the guard trigger off:
--
--   alter table public.member disable trigger member_guard_privileged_columns;
--
-- The guard lets only an admin move an auth mapping and there is no admin
-- session yet, so this fixture cannot be built through the front door. The
-- trigger goes straight back on before anything is actually under test, and
-- the whole transaction rolls back regardless.

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
  -- Release the roster (see the header), then sign in the way the app does.
  alter table public.member disable trigger member_guard_privileged_columns;
  update public.member set auth_user_id = null;
  alter table public.member enable trigger member_guard_privileged_columns;

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
  alter table public.member disable trigger member_guard_privileged_columns;
  update public.member set auth_user_id = null;
  alter table public.member enable trigger member_guard_privileged_columns;

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
  alter table public.member disable trigger member_guard_privileged_columns;
  update public.member set auth_user_id = null;
  alter table public.member enable trigger member_guard_privileged_columns;

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

-- ===========================================================================
-- 9. The ledger sign convention is enforced per kind, not left to the caller.
--    positive = the member owes more. A payment must reduce the balance and a
--    payout must increase it; getting either backwards would silently corrupt
--    every balance, so the database refuses both.
-- ===========================================================================
begin;
do $$
declare
  v_blocked text;
begin
  begin
    insert into public.ledger_entry
      (company_id, member_id, kind, entry_date, description, amount, gl_account_code)
    values ('00000000-0000-0000-0000-00000000c000',
            '00000000-0000-0000-0000-00000000a001',
            'payment', date '2026-03-01', 'e-Transfer received', 500.00, '1000');
    v_blocked := null;
  exception when others then
    v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a positive payment was accepted';
  end if;

  begin
    insert into public.ledger_entry
      (company_id, member_id, kind, entry_date, description, amount, gl_account_code)
    values ('00000000-0000-0000-0000-00000000c000',
            '00000000-0000-0000-0000-00000000a001',
            'payout', date '2026-03-01', 'Reimbursement sent', -150.00, '1000');
    v_blocked := null;
  exception when others then
    v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a negative payout was accepted';
  end if;

  -- GST cannot be claimed on a line that carries no tax.
  begin
    insert into public.ledger_entry
      (company_id, member_id, kind, entry_date, description,
       amount, gst_amount, tax_treatment, gl_account_code)
    values ('00000000-0000-0000-0000-00000000c000',
            '00000000-0000-0000-0000-00000000a001',
            'insurance', date '2026-03-01', 'Insurance share',
            450.00, 22.50, 'out_of_scope', '4500');
    v_blocked := null;
  exception when others then
    v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  GST was accepted on an out-of-scope line';
  end if;

  -- The correctly-signed payment must still go in.
  insert into public.ledger_entry
    (company_id, member_id, kind, entry_date, description, amount, gl_account_code)
  values ('00000000-0000-0000-0000-00000000c000',
          '00000000-0000-0000-0000-00000000a001',
          'payment', date '2026-03-01', 'e-Transfer received', -500.00, '1000');

  raise notice 'PASS  the ledger sign convention is enforced per kind';
end $$;
rollback;

-- ===========================================================================
-- 10. A draft invoice is a proposal, not a debt. Its lines must not count
--     toward a balance until it is issued, and a void invoice never counts.
-- ===========================================================================
begin;
do $$
declare
  v_base    numeric;
  v_balance numeric;
  v_total   numeric;
begin
  -- Measured as a CHANGE from where the member already stood, not against
  -- zero. The seed carries a closed September and an open October, so "the
  -- balance is zero" was only ever true of an empty database, and an absolute
  -- figure here would have to be rewritten every time the seed grows.
  v_base := public.member_balance('00000000-0000-0000-0000-00000000a001');

  insert into public.invoice (id, company_id, member_id, period_month)
  values ('00000000-0000-0000-0000-00000000f001',
          '00000000-0000-0000-0000-00000000c000',
          '00000000-0000-0000-0000-00000000a001',
          date '2026-03-01');

  insert into public.ledger_entry
    (company_id, member_id, invoice_id, kind, entry_date, description,
     quantity, unit_rate, amount, gl_account_code)
  values ('00000000-0000-0000-0000-00000000c000',
          '00000000-0000-0000-0000-00000000a001',
          '00000000-0000-0000-0000-00000000f001',
          'flight_charge', date '2026-03-15', '3.5 hr x $285.00',
          3.5, 285.0000, 997.50, '4100');

  v_balance := public.member_balance('00000000-0000-0000-0000-00000000a001');
  v_total   := public.invoice_total('00000000-0000-0000-0000-00000000f001');

  if v_balance <> v_base then
    raise exception 'FAIL  a draft invoice moved the balance by %', v_balance - v_base;
  end if;
  -- The draft total is still readable; it is what the review screen shows.
  if v_total <> 997.50 then
    raise exception 'FAIL  draft invoice total is %', v_total;
  end if;

  update public.invoice
     set status    = 'issued',
         number    = public.next_invoice_number('00000000-0000-0000-0000-00000000c000'),
         issued_at = now()
   where id = '00000000-0000-0000-0000-00000000f001';

  v_balance := public.member_balance('00000000-0000-0000-0000-00000000a001');
  if v_balance <> v_base + 997.50 then
    raise exception 'FAIL  issuing moved the balance by %', v_balance - v_base;
  end if;

  update public.invoice set status = 'void'
   where id = '00000000-0000-0000-0000-00000000f001';

  v_balance := public.member_balance('00000000-0000-0000-0000-00000000a001');
  if v_balance <> v_base then
    raise exception 'FAIL  a void invoice still owes %', v_balance - v_base;
  end if;

  raise notice 'PASS  only an issued invoice counts toward a balance';
end $$;
rollback;

-- ===========================================================================
-- 11. SPEC.md 4.6: "a sent invoice never changes silently." Once issued, the
--     invoice and its lines are frozen; a correction becomes an adjustment.
-- ===========================================================================
begin;

insert into public.invoice (id, company_id, member_id, period_month, status, number, issued_at)
values ('00000000-0000-0000-0000-00000000f002',
        '00000000-0000-0000-0000-00000000c000',
        '00000000-0000-0000-0000-00000000a001',
        date '2026-04-01', 'issued', 9001, now());

insert into public.ledger_entry
  (id, company_id, member_id, invoice_id, kind, entry_date, description,
   amount, gl_account_code)
values ('00000000-0000-0000-0000-00000000e001',
        '00000000-0000-0000-0000-00000000c000',
        '00000000-0000-0000-0000-00000000a001',
        '00000000-0000-0000-0000-00000000f002',
        'flight_charge', date '2026-04-10', '1.0 hr x $285.00',
        285.00, '4100');

do $$
declare
  v_blocked text;
begin
  begin
    update public.ledger_entry set amount = 1.00
     where id = '00000000-0000-0000-0000-00000000e001';
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a line on an issued invoice was repriced';
  end if;

  begin
    delete from public.ledger_entry
     where id = '00000000-0000-0000-0000-00000000e001';
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a line on an issued invoice was deleted';
  end if;

  -- Detaching the line first must not open a back door: the guard reads the
  -- OLD row's invoice, so this is still blocked.
  begin
    update public.ledger_entry set invoice_id = null
     where id = '00000000-0000-0000-0000-00000000e001';
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a line was detached from an issued invoice';
  end if;

  begin
    update public.invoice set period_month = date '2026-05-01'
     where id = '00000000-0000-0000-0000-00000000f002';
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  an issued invoice was re-dated';
  end if;

  begin
    delete from public.invoice where id = '00000000-0000-0000-0000-00000000f002';
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  an issued invoice was deleted';
  end if;

  -- The push to the accounting system writes these after issuing, by
  -- definition, so they must stay writable.
  update public.ledger_entry set external_ref = 'qbo:42', synced_at = now()
   where id = '00000000-0000-0000-0000-00000000e001';

  -- Status may only advance.
  update public.invoice set status = 'settled', settled_at = now()
   where id = '00000000-0000-0000-0000-00000000f002';

  begin
    update public.invoice set status = 'issued'
     where id = '00000000-0000-0000-0000-00000000f002';
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a settled invoice went back to issued';
  end if;

  raise notice 'PASS  an issued invoice and its lines are immutable';
end $$;
rollback;

-- ===========================================================================
-- 12. Invoice numbers are allocated one at a time and never reused. GST
--     invoices must be gapless, which is why this is a counter row and not a
--     sequence: a sequence would not roll back with the transaction.
-- ===========================================================================
begin;
do $$
declare
  v_first  bigint;
  v_second bigint;
  v_blocked text;
begin
  v_first  := public.next_invoice_number('00000000-0000-0000-0000-00000000c000');
  v_second := public.next_invoice_number('00000000-0000-0000-0000-00000000c000');

  if v_second <> v_first + 1 then
    raise exception 'FAIL  numbering jumped from % to %', v_first, v_second;
  end if;

  insert into public.invoice (company_id, member_id, period_month, status, number, issued_at)
  values ('00000000-0000-0000-0000-00000000c000',
          '00000000-0000-0000-0000-00000000a001',
          date '2026-06-01', 'issued', v_first, now());

  begin
    insert into public.invoice (company_id, member_id, period_month, status, number, issued_at)
    values ('00000000-0000-0000-0000-00000000c000',
            '00000000-0000-0000-0000-00000000a002',
            date '2026-06-01', 'issued', v_first, now());
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  two invoices share number %', v_first;
  end if;

  -- A draft must not carry a number, and anything past draft must.
  begin
    insert into public.invoice (company_id, member_id, period_month, number)
    values ('00000000-0000-0000-0000-00000000c000',
            '00000000-0000-0000-0000-00000000a002',
            date '2026-07-01', v_second);
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a draft invoice was given a number';
  end if;

  raise notice 'PASS  invoice numbers are sequential and unique';
end $$;
rollback;

-- ===========================================================================
-- 13. A pilot sees their own money and nobody else's -- including through the
--     views, which only filter because they were created with
--     security_invoker. A view defaults to running as its owner, which would
--     bypass RLS and show every owner's ledger to everyone.
-- ===========================================================================
begin;

do $$
begin
  -- Fixture from legitimate paths only: both owners claim their row, then the
  -- admin demotes the second to pilot.
  alter table public.member disable trigger member_guard_privileged_columns;
  update public.member set auth_user_id = null;
  alter table public.member enable trigger member_guard_privileged_columns;

  perform set_config('role', 'authenticated', true);

  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a0010",
      "email":"owner2@example.test"}', true);
  perform public.claim_member_identity();

  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a0011",
      "email":"owner1@example.test"}', true);
  perform public.claim_member_identity();

  update public.member set role = 'pilot'
   where id = '00000000-0000-0000-0000-00000000a002';

  perform set_config('role', 'postgres', true);
end $$;

-- One issued invoice with one line for each owner.
insert into public.invoice (id, company_id, member_id, period_month, status, number, issued_at) values
  ('00000000-0000-0000-0000-00000000f003', '00000000-0000-0000-0000-00000000c000',
   '00000000-0000-0000-0000-00000000a001', date '2026-08-01', 'issued', 9101, now()),
  ('00000000-0000-0000-0000-00000000f004', '00000000-0000-0000-0000-00000000c000',
   '00000000-0000-0000-0000-00000000a002', date '2026-08-01', 'issued', 9102, now());

insert into public.ledger_entry
  (company_id, member_id, invoice_id, kind, entry_date, description, amount, gl_account_code) values
  ('00000000-0000-0000-0000-00000000c000', '00000000-0000-0000-0000-00000000a001',
   '00000000-0000-0000-0000-00000000f003', 'flight_charge', date '2026-08-10',
   'Owner one flight', 285.00, '4100'),
  ('00000000-0000-0000-0000-00000000c000', '00000000-0000-0000-0000-00000000a002',
   '00000000-0000-0000-0000-00000000f004', 'flight_charge', date '2026-08-11',
   'Owner two flight', 570.00, '4100');

do $$
declare
  v_entries  int;
  v_own      int;
  v_posted   int;
  v_journal  int;
  v_invoices int;
  v_balance  numeric;
  v_blocked  text;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
                     '{"sub":"00000000-0000-0000-0000-0000000a0010"}', true);

  -- Counted as "someone else's" and "mine", not as a total. A count proves
  -- nothing on its own about WHICH rows came back, and an absolute total would
  -- have to be rewritten every time the seed grows a month.
  select count(*) filter (where member_id <> '00000000-0000-0000-0000-00000000a002'),
         count(*) filter (where member_id =  '00000000-0000-0000-0000-00000000a002')
    into v_entries, v_own
  from public.ledger_entry;
  select count(*) into v_posted
    from public.ledger_entry_posted
   where member_id <> '00000000-0000-0000-0000-00000000a002';
  select count(*) into v_journal
    from public.gl_journal
   where member_id <> '00000000-0000-0000-0000-00000000a002';
  select count(*) into v_invoices
    from public.invoice
   where member_id <> '00000000-0000-0000-0000-00000000a002';
  v_balance := public.member_balance('00000000-0000-0000-0000-00000000a001');

  -- A pilot must not be able to write money rows at all.
  begin
    insert into public.ledger_entry
      (company_id, member_id, kind, entry_date, description, amount, gl_account_code)
    values ('00000000-0000-0000-0000-00000000c000',
            '00000000-0000-0000-0000-00000000a002',
            'payment', date '2026-08-20', 'Paid, honest', -570.00, '1000');
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;

  perform set_config('role', 'postgres', true);

  if v_entries <> 0 then
    raise exception 'FAIL  a pilot read % of another owner''s ledger entries', v_entries;
  end if;
  -- And the other half of the claim: their own rows did come back, so the zero
  -- above is RLS filtering rather than an empty table.
  if v_own = 0 then
    raise exception 'FAIL  a pilot could not read their own ledger at all';
  end if;
  if v_posted <> 0 then
    raise exception 'FAIL  a pilot read % foreign rows through ledger_entry_posted', v_posted;
  end if;
  if v_journal <> 0 then
    raise exception 'FAIL  a pilot read % foreign rows through gl_journal', v_journal;
  end if;
  if v_invoices <> 0 then
    raise exception 'FAIL  a pilot read % of another owner''s invoices', v_invoices;
  end if;
  if v_balance <> 0 then
    raise exception 'FAIL  a pilot read another owner''s balance as %', v_balance;
  end if;
  if v_blocked is null then
    raise exception 'FAIL  a pilot recorded their own payment';
  end if;

  raise notice 'PASS  a pilot sees only their own ledger, invoices and journal';
end $$;
rollback;

-- ===========================================================================
-- 14. A charge cannot land on another member's bill. Nothing else in the
--     schema would stop it, and it would bill the wrong person.
-- ===========================================================================
begin;

insert into public.invoice (id, company_id, member_id, period_month, status, number, issued_at)
values ('00000000-0000-0000-0000-00000000f005',
        '00000000-0000-0000-0000-00000000c000',
        '00000000-0000-0000-0000-00000000a001',
        -- A month the seed does not use: an invoice is unique per member and
        -- month, so borrowing September would collide with the seeded close.
        date '2026-04-01', 'issued', 9201, now());

do $$
declare
  v_blocked text;
begin
  begin
    insert into public.ledger_entry
      (company_id, member_id, invoice_id, kind, entry_date, description,
       amount, gl_account_code)
    values ('00000000-0000-0000-0000-00000000c000',
            '00000000-0000-0000-0000-00000000a002',
            '00000000-0000-0000-0000-00000000f005',
            'flight_charge', date '2026-04-10', 'Wrong owner', 285.00, '4100');
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;

  if v_blocked is null then
    raise exception 'FAIL  one owner''s charge landed on another owner''s invoice';
  end if;
  raise notice 'PASS  an invoice line must belong to the invoiced member';
end $$;
rollback;

-- ===========================================================================
-- 15. The journal balances. Every ledger entry becomes a debit and a credit of
--     the same size, so any complete set of rows nets to zero -- which is what
--     the accounting system will reject the import for if it ever stops being
--     true.
-- ===========================================================================
begin;

insert into public.invoice (id, company_id, member_id, period_month, status, number, issued_at)
values ('00000000-0000-0000-0000-00000000f006',
        '00000000-0000-0000-0000-00000000c000',
        '00000000-0000-0000-0000-00000000a001',
        -- May, because the assertions below count rows in a date window and the
        -- seed posts a payment in October. A window that catches seed rows
        -- would be measuring the seed, not the journal.
        date '2026-05-01', 'issued', 9301, now());

insert into public.ledger_entry
  (company_id, member_id, invoice_id, kind, entry_date, description,
   amount, gl_account_code) values
  ('00000000-0000-0000-0000-00000000c000', '00000000-0000-0000-0000-00000000a001',
   '00000000-0000-0000-0000-00000000f006', 'flight_charge', date '2026-05-05',
   '2.0 hr x $285.00', 570.00, '4100'),
  ('00000000-0000-0000-0000-00000000c000', '00000000-0000-0000-0000-00000000a001',
   null, 'payment', date '2026-05-20', 'e-Transfer received', -570.00, '1000');

do $$
declare
  v_net    numeric;
  v_rows   int;
  v_ar     numeric;
  v_bank   numeric;
begin
  select coalesce(sum(debit_credit), 0), count(*) into v_net, v_rows
  from public.gl_journal
  where entry_date between date '2026-05-01' and date '2026-05-31';

  if v_net <> 0 then
    raise exception 'FAIL  the journal nets to % over the month', v_net;
  end if;
  if v_rows <> 4 then
    raise exception 'FAIL  two entries produced % journal lines', v_rows;
  end if;

  -- The charge debits receivables; the payment credits them and debits the bank.
  select coalesce(sum(debit_credit), 0) into v_ar
  from public.gl_journal
  where gl_account_code = '1100' and entry_date >= date '2026-05-01'
                                 and entry_date <= date '2026-05-31';
  select coalesce(sum(debit_credit), 0) into v_bank
  from public.gl_journal
  where gl_account_code = '1000' and entry_date >= date '2026-05-01'
                                 and entry_date <= date '2026-05-31';

  if v_ar <> 0 then
    raise exception 'FAIL  receivables net to % after a charge and its payment', v_ar;
  end if;
  if v_bank <> 570.00 then
    raise exception 'FAIL  the bank was debited % for a $570 payment', v_bank;
  end if;

  raise notice 'PASS  the journal balances and posts cash to the bank account';
end $$;
rollback;

-- ===========================================================================
-- 16. Rates are shared configuration: readable by every owner, writable only
--     by an admin. A pilot who could edit a rate component could reprice their
--     own flying.
-- ===========================================================================
begin;
do $$
declare
  v_read int;
  v_rows int;
begin
  alter table public.member disable trigger member_guard_privileged_columns;
  update public.member set auth_user_id = null;
  alter table public.member enable trigger member_guard_privileged_columns;

  perform set_config('role', 'authenticated', true);

  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a0012",
      "email":"owner2@example.test"}', true);
  perform public.claim_member_identity();

  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a0013",
      "email":"owner1@example.test"}', true);
  perform public.claim_member_identity();

  update public.member set role = 'pilot'
   where id = '00000000-0000-0000-0000-00000000a002';

  perform set_config('request.jwt.claims',
                     '{"sub":"00000000-0000-0000-0000-0000000a0012"}', true);

  select count(*) into v_read from public.rate_component;

  update public.rate_component set rate_per_hour = 1.0000
   where gl_account_code = '4100';
  get diagnostics v_rows = row_count;

  perform set_config('role', 'postgres', true);

  if v_read < 6 then
    raise exception 'FAIL  a pilot could only read % rate component(s)', v_read;
  end if;
  if v_rows <> 0 then
    raise exception 'FAIL  a pilot repriced % rate component(s)', v_rows;
  end if;
  raise notice 'PASS  a pilot can read rates but not change them';
end $$;
rollback;

-- ===========================================================================
-- 17. A flight's hours are derived, never typed. The two rounding rules differ
--     on purpose -- billed rounds up because it is a charge, est tach rounds to
--     nearest because it is an engine-life estimate -- and both must be taken
--     from the exact interval rather than from the already-rounded
--     flight_hours column.
-- ===========================================================================
begin;
do $$
declare
  v_flight public.flight;
begin
  -- Still running: there is nothing to bill yet.
  insert into public.flight (aircraft_id, pilot_member_id, start_at)
  values ('00000000-0000-0000-0000-0000000ac001',
          '00000000-0000-0000-0000-00000000a001',
          timestamptz '2026-10-12 19:03:00-07')
  returning * into v_flight;

  if v_flight.billed_hours is not null or v_flight.est_tach_hours is not null then
    raise exception 'FAIL  a running flight already bills % hr', v_flight.billed_hours;
  end if;
  -- The snapshot is taken at insert, from the aircraft, without the caller
  -- having to remember it.
  if v_flight.tach_factor_used <> 1.300 then
    raise exception 'FAIL  tach factor snapshot is %', v_flight.tach_factor_used;
  end if;

  -- Stopping the clock prices it: one hour, 1/1.3 = 0.769 -> 0.8 tach.
  update public.flight set end_at = timestamptz '2026-10-12 20:03:00-07'
   where id = v_flight.id returning * into v_flight;

  if (v_flight.flight_hours, v_flight.billed_hours, v_flight.est_tach_hours)
     is distinct from (1.00, 1.00, 0.80) then
    raise exception 'FAIL  one hour priced as %/%/%',
      v_flight.flight_hours, v_flight.billed_hours, v_flight.est_tach_hours;
  end if;

  -- The double-rounding trap. 2537 s is 0.704722 hr, which flight_hours stores
  -- as 0.70. Rounding that up gives 0.7; rounding the exact value up gives 0.8,
  -- and 0.8 is what the owner is owed.
  update public.flight
     set end_at = v_flight.start_at + interval '2537 seconds'
   where id = v_flight.id returning * into v_flight;

  if v_flight.flight_hours is distinct from 0.70 then
    raise exception 'FAIL  2537 s stored as % hr', v_flight.flight_hours;
  end if;
  if v_flight.billed_hours is distinct from 0.80 then
    raise exception 'FAIL  0.7047 hr billed as % -- rounded twice', v_flight.billed_hours;
  end if;

  -- The 48-minute worked example from the Confirm screen.
  update public.flight set end_at = v_flight.start_at + interval '48 minutes'
   where id = v_flight.id returning * into v_flight;
  if (v_flight.billed_hours, v_flight.est_tach_hours) is distinct from (0.80, 0.60) then
    raise exception 'FAIL  48 min priced as % billed / % tach',
      v_flight.billed_hours, v_flight.est_tach_hours;
  end if;

  -- Retuning the aircraft's factor must not restate a flight already logged.
  update public.aircraft set tach_factor = 1.500
   where id = '00000000-0000-0000-0000-0000000ac001';
  update public.flight set notes = 'touch'
   where id = v_flight.id returning * into v_flight;

  if v_flight.tach_factor_used is distinct from 1.300
     or v_flight.est_tach_hours is distinct from 0.60 then
    raise exception 'FAIL  retuning the factor restated the flight to %/% ',
      v_flight.tach_factor_used, v_flight.est_tach_hours;
  end if;

  raise notice 'PASS  flight hours are derived, snapshot and rounded per rule';
end $$;
rollback;

-- ===========================================================================
-- 18. One clock per aeroplane. Two pilots cannot both be flying it, and a
--     double-tapped Start must not open a second flight. The partial unique
--     index is the real guard; timer_start turns it into an explanation.
-- ===========================================================================
begin;

insert into public.api_token (member_id, token_hash, label) values
  ('00000000-0000-0000-0000-00000000a001', repeat('a', 64), 'owner one'),
  ('00000000-0000-0000-0000-00000000a002', repeat('b', 64), 'owner two');

do $$
declare
  v_first   public.flight;
  v_again   public.flight;
  v_blocked text;
  v_count   int;
begin
  v_first := public.timer_start(repeat('a', 64));

  -- Same pilot taps Start twice: their own running flight comes back.
  v_again := public.timer_start(repeat('a', 64));
  if v_again.id <> v_first.id then
    raise exception 'FAIL  a second Start opened flight %', v_again.id;
  end if;

  -- The other owner cannot start one on top of it, and cannot stop it either.
  begin
    perform public.timer_start(repeat('b', 64));
    v_blocked := null;
  exception when others then v_blocked := sqlstate;
  end;
  if v_blocked is distinct from '55006' then
    raise exception 'FAIL  a second pilot started on a flying aeroplane (%)', v_blocked;
  end if;

  begin
    perform public.timer_stop(repeat('b', 64));
    v_blocked := null;
  exception when others then v_blocked := sqlstate;
  end;
  if v_blocked is distinct from '42501' then
    raise exception 'FAIL  a second pilot stopped another pilot''s flight (%)', v_blocked;
  end if;

  -- And the index itself, not just the function that avoids tripping it.
  begin
    insert into public.flight (aircraft_id, pilot_member_id, tach_factor_used)
    values ('00000000-0000-0000-0000-0000000ac001',
            '00000000-0000-0000-0000-00000000a002', 1.300);
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a direct insert opened a second running flight';
  end if;

  select count(*) into v_count from public.flight where end_at is null;
  if v_count <> 1 then
    raise exception 'FAIL  % flights are running', v_count;
  end if;

  -- now() is the TRANSACTION timestamp, so a start and a stop in one
  -- transaction would land on the same instant and fail the ends-after-start
  -- check. In the app they are separate requests; here the clock is wound back.
  update public.flight set start_at = start_at - interval '30 minutes'
   where id = v_first.id;

  -- Stopping leaves it a draft for the Confirm screen, not confirmed.
  v_again := public.timer_stop(repeat('a', 64));
  if v_again.id <> v_first.id or v_again.status <> 'draft' then
    raise exception 'FAIL  stop returned flight % as %', v_again.id, v_again.status;
  end if;
  if v_again.end_at is null then
    raise exception 'FAIL  the clock is still running after Stop';
  end if;

  -- Stopping again has nothing to stop; it must say so rather than invent one.
  begin
    perform public.timer_stop(repeat('a', 64));
    v_blocked := null;
  exception when others then v_blocked := sqlstate;
  end;
  if v_blocked is distinct from '55006' then
    raise exception 'FAIL  Stop on a parked aeroplane gave %', v_blocked;
  end if;

  raise notice 'PASS  one clock per aeroplane, and only its pilot stops it';
end $$;
rollback;

-- ===========================================================================
-- 19. A retry is not a second flight. The Shortcut fires over a flaky
--     connection, so the same idempotency key must return the same row --
--     including after the flight has been stopped, when the aeroplane no
--     longer has a running flight to fall back on.
-- ===========================================================================
begin;

insert into public.api_token (member_id, token_hash, label)
values ('00000000-0000-0000-0000-00000000a001', repeat('c', 64), 'shortcut');

do $$
declare
  v_a      public.flight;
  v_b      public.flight;
  v_count  int;
  -- Counted as "how many did these four calls add", not "how many exist": the
  -- seed flies the aeroplane, and an absolute figure would be counting it.
  v_before int;
begin
  select count(*) into v_before from public.flight;

  v_a := public.timer_start(repeat('c', 64), 48.65, -123.4, 12, 'key-start-1');
  -- Wind the clock back, because now() does not move within a transaction.
  update public.flight set start_at = start_at - interval '30 minutes'
   where id = v_a.id;
  v_b := public.timer_stop (repeat('c', 64), 48.42, -123.37, 9, 'key-stop-1');

  -- Replay both, in the state the app is actually in: parked.
  v_b := public.timer_start(repeat('c', 64), 48.65, -123.4, 12, 'key-start-1');
  if v_b.id <> v_a.id then
    raise exception 'FAIL  a replayed Start opened flight %', v_b.id;
  end if;
  v_b := public.timer_stop(repeat('c', 64), 48.42, -123.37, 9, 'key-stop-1');
  if v_b.id <> v_a.id then
    raise exception 'FAIL  a replayed Stop touched flight %', v_b.id;
  end if;

  select count(*) into v_count from public.flight;
  if v_count <> v_before + 1 then
    raise exception 'FAIL  four calls left % new flights', v_count - v_before;
  end if;

  -- Both fixes were recorded, and the replay did not duplicate them.
  select count(*) into v_count from public.flight_fix where flight_id = v_a.id;
  if v_count <> 2 then
    raise exception 'FAIL  % GPS fix(es) recorded', v_count;
  end if;

  -- The flight row carries the non-identifying metadata; the coordinates do
  -- not live here.
  select * into v_b from public.flight where id = v_a.id;
  if v_b.start_fix_at is null or v_b.start_fix_accuracy_m is distinct from 12 then
    raise exception 'FAIL  start fix metadata is %/%',
      v_b.start_fix_at, v_b.start_fix_accuracy_m;
  end if;

  raise notice 'PASS  replayed timer calls return the same flight';
end $$;
rollback;

-- ===========================================================================
-- 20. SPEC.md 4.2: a fix taken at Stop can be a home address. The flight log is
--     shared, the coordinates are not. This is why the fixes are rows and not
--     columns -- RLS cannot restrict a column.
-- ===========================================================================
begin;

insert into public.flight (id, aircraft_id, pilot_member_id, tach_factor_used,
                           start_at, end_at, start_fix_at, start_fix_accuracy_m)
values ('00000000-0000-0000-0000-00000000b001',
        '00000000-0000-0000-0000-0000000ac001',
        '00000000-0000-0000-0000-00000000a001', 1.300,
        timestamptz '2026-10-12 19:03:00-07',
        timestamptz '2026-10-12 20:03:00-07',
        timestamptz '2026-10-12 19:03:00-07', 12);

insert into public.flight_fix (flight_id, which, lat, lon, accuracy_m)
values ('00000000-0000-0000-0000-00000000b001', 'start', 48.650000, -123.400000, 12);

do $$
declare
  v_flights int;
  v_fixes   int;
  v_billed  numeric;
  v_blocked text;
begin
  -- Fixture from legitimate paths only: both owners claim their row, then the
  -- admin demotes the second to pilot.
  alter table public.member disable trigger member_guard_privileged_columns;
  update public.member set auth_user_id = null;
  alter table public.member enable trigger member_guard_privileged_columns;

  perform set_config('role', 'authenticated', true);

  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a0020",
      "email":"owner2@example.test"}', true);
  perform public.claim_member_identity();

  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a0021",
      "email":"owner1@example.test"}', true);
  perform public.claim_member_identity();

  update public.member set role = 'pilot'
   where id = '00000000-0000-0000-0000-00000000a002';

  perform set_config('request.jwt.claims',
                     '{"sub":"00000000-0000-0000-0000-0000000a0020"}', true);

  -- The co-owner can read the flight -- who flew, when, and what it cost.
  select count(*), max(billed_hours) into v_flights, v_billed
  from public.flight where id = '00000000-0000-0000-0000-00000000b001';

  -- But not where the aeroplane was.
  select count(*) into v_fixes from public.flight_fix;

  -- Nor can they plant one on someone else's flight. A with-check violation
  -- raises rather than filtering, so this is caught rather than counted.
  begin
    insert into public.flight_fix (flight_id, which, lat, lon)
    values ('00000000-0000-0000-0000-00000000b001', 'end', 0, 0);
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;

  perform set_config('role', 'postgres', true);

  if v_flights <> 1 or v_billed is distinct from 1.00 then
    raise exception 'FAIL  a co-owner read % flight(s) billing %', v_flights, v_billed;
  end if;
  if v_fixes <> 0 then
    raise exception 'FAIL  a co-owner read % GPS fix(es)', v_fixes;
  end if;
  if v_blocked is null then
    raise exception 'FAIL  a co-owner wrote a fix onto another pilot''s flight';
  end if;

  -- "Discard the raw end fix" must not erase the flight's own history: the
  -- accuracy and timing stay on the flight row, which is why they are columns
  -- there rather than only on the fix.
  delete from public.flight_fix
   where flight_id = '00000000-0000-0000-0000-00000000b001';

  -- `is distinct from`, not `<>`: erasing the column leaves NULL, and NULL <> 12
  -- is NULL, which would skip the RAISE and let this pass vacuously.
  if (select start_fix_accuracy_m from public.flight
       where id = '00000000-0000-0000-0000-00000000b001') is distinct from 12 then
    raise exception 'FAIL  discarding a fix erased the flight''s fix metadata';
  end if;

  raise notice 'PASS  the flight log is shared, the coordinates are not';
end $$;
rollback;

-- ===========================================================================
-- 21. SPEC.md 4.6: once a month is closed the flights behind the bill are
--     frozen, and a correction becomes an adjustment. Notes stay editable --
--     remembering where you went is not repricing the flight.
-- ===========================================================================
begin;

insert into public.invoice (id, company_id, member_id, period_month, status, number, issued_at)
values ('00000000-0000-0000-0000-00000000f007',
        '00000000-0000-0000-0000-00000000c000',
        '00000000-0000-0000-0000-00000000a001',
        date '2026-11-01', 'issued', 9401, now());

insert into public.flight (id, aircraft_id, pilot_member_id, tach_factor_used,
                           start_at, end_at, status, invoice_id)
values ('00000000-0000-0000-0000-00000000b002',
        '00000000-0000-0000-0000-0000000ac001',
        '00000000-0000-0000-0000-00000000a001', 1.300,
        timestamptz '2026-11-02 10:00:00-08',
        timestamptz '2026-11-02 11:00:00-08',
        'billed', '00000000-0000-0000-0000-00000000f007');

do $$
declare
  v_blocked text;
begin
  begin
    update public.flight set end_at = timestamptz '2026-11-02 13:00:00-08'
     where id = '00000000-0000-0000-0000-00000000b002';
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a billed flight was re-timed';
  end if;

  begin
    update public.flight set pilot_member_id = '00000000-0000-0000-0000-00000000a002'
     where id = '00000000-0000-0000-0000-00000000b002';
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a billed flight was moved to another pilot';
  end if;

  begin
    delete from public.flight where id = '00000000-0000-0000-0000-00000000b002';
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a billed flight was deleted';
  end if;

  -- Still a logbook: the notes and the tach reading may be filled in later.
  update public.flight set notes = 'Ganges and back', actual_tach_hours = 1234.5
   where id = '00000000-0000-0000-0000-00000000b002';

  -- A billed flight must keep its invoice, and an unbilled one must not have
  -- an invoice at all. The constraint is an equivalence in both directions.
  begin
    insert into public.flight (aircraft_id, pilot_member_id, tach_factor_used,
                               start_at, end_at, status, invoice_id)
    values ('00000000-0000-0000-0000-0000000ac001',
            '00000000-0000-0000-0000-00000000a001', 1.300,
            timestamptz '2026-11-03 10:00:00-08',
            timestamptz '2026-11-03 11:00:00-08',
            'confirmed', '00000000-0000-0000-0000-00000000f007');
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  an unbilled flight was attached to an invoice';
  end if;

  -- And a flight cannot be confirmed while the clock is still running.
  begin
    insert into public.flight (aircraft_id, pilot_member_id, tach_factor_used, status)
    values ('00000000-0000-0000-0000-0000000ac001',
            '00000000-0000-0000-0000-00000000a001', 1.300, 'confirmed');
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a flight was confirmed with no end time';
  end if;

  raise notice 'PASS  a billed flight is frozen except for its notes';
end $$;
rollback;

-- ===========================================================================
-- 22. The token is the whole credential, so every way it can be invalid has to
--     fail the same way -- and a token hash is a credential digest no other
--     owner should hold, admin or not.
-- ===========================================================================
begin;

insert into public.api_token (member_id, token_hash, label, revoked_at) values
  ('00000000-0000-0000-0000-00000000a001', repeat('d', 64), 'live',    null),
  ('00000000-0000-0000-0000-00000000a001', repeat('e', 64), 'revoked', now());

do $$
declare
  v_state text;
  v_seen  int;
begin
  foreach v_state in array array[repeat('e', 64), repeat('f', 64), 'short', null]
  loop
    begin
      perform public.member_for_token_hash(v_state);
      raise exception 'FAIL  token % was accepted', coalesce(v_state, 'null');
    exception when sqlstate '28000' then
      null;
    end;
  end loop;

  -- The live one still works, so the test above is not passing vacuously.
  if public.member_for_token_hash(repeat('d', 64))
     <> '00000000-0000-0000-0000-00000000a001' then
    raise exception 'FAIL  a live token did not resolve to its member';
  end if;

  -- A deactivated member's token stops working without anyone revoking it.
  -- Deactivating is an admin action and there is no admin session here, so the
  -- guard comes off for the fixture the same way as above.
  alter table public.member disable trigger member_guard_privileged_columns;
  update public.member set is_active = false
   where id = '00000000-0000-0000-0000-00000000a001';
  alter table public.member enable trigger member_guard_privileged_columns;

  begin
    perform public.member_for_token_hash(repeat('d', 64));
    raise exception 'FAIL  a deactivated member''s token still works';
  exception when sqlstate '28000' then
    null;
  end;

  alter table public.member disable trigger member_guard_privileged_columns;
  update public.member set is_active = true
   where id = '00000000-0000-0000-0000-00000000a001';
  alter table public.member enable trigger member_guard_privileged_columns;

  -- The other owner is an admin, and still must not see the digest.
  alter table public.member disable trigger member_guard_privileged_columns;
  update public.member set auth_user_id = null;
  alter table public.member enable trigger member_guard_privileged_columns;

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a0022",
      "email":"owner2@example.test"}', true);
  perform public.claim_member_identity();

  select count(*) into v_seen from public.api_token;

  perform set_config('role', 'postgres', true);

  if v_seen <> 0 then
    raise exception 'FAIL  an admin read % of another owner''s token digests', v_seen;
  end if;
  raise notice 'PASS  only a live token authenticates, and digests stay private';
end $$;
rollback;

-- ===========================================================================
-- 23. SPEC.md 4.4: the tach is an ESTIMATE between readings -- the last real
--     reading plus the estimated tach of every flight since -- and logging a
--     reading "resets its running estimate to match". The reset is not a
--     separate step: a newer reading simply becomes the datum, and the flights
--     behind it stop counting.
-- ===========================================================================
begin;
do $$
declare
  v_est numeric;
begin
  -- The test lays its own datum rather than borrowing the seed's opening
  -- reading. The claim being tested is that the estimate runs forward from the
  -- NEWEST reading, so a test that started from the oldest one would have to
  -- know everything the seed has flown since -- and would break every time the
  -- seed grew a flight, which is exactly what happened when it did.
  insert into public.tach_reading (aircraft_id, reading, read_at, read_by)
  values ('00000000-0000-0000-0000-0000000ac001', 500.00,
          timestamptz '2026-10-20 09:00:00-07',
          '00000000-0000-0000-0000-00000000a001');

  v_est := public.aircraft_tach_estimate('00000000-0000-0000-0000-0000000ac001');
  if v_est is distinct from 500.00 then
    raise exception 'FAIL  with nothing flown since, the estimate is % not the reading', v_est;
  end if;

  -- Two one-hour flights after the reading: 1/1.3 = 0.769 -> 0.8 tach each.
  insert into public.flight (aircraft_id, pilot_member_id, start_at, end_at)
  values ('00000000-0000-0000-0000-0000000ac001',
          '00000000-0000-0000-0000-00000000a001',
          timestamptz '2026-10-21 10:00:00-07',
          timestamptz '2026-10-21 11:00:00-07'),
         ('00000000-0000-0000-0000-0000000ac001',
          '00000000-0000-0000-0000-00000000a001',
          timestamptz '2026-10-22 10:00:00-07',
          timestamptz '2026-10-22 11:00:00-07');

  v_est := public.aircraft_tach_estimate('00000000-0000-0000-0000-0000000ac001');
  if v_est is distinct from 501.60 then
    raise exception 'FAIL  two 0.8 hr flights estimated the tach at %', v_est;
  end if;

  -- The meter actually says 505.0. Nothing is reset by hand; the new reading
  -- is simply newer, so the two flights above are now behind it.
  insert into public.tach_reading (aircraft_id, reading, read_at, read_by)
  values ('00000000-0000-0000-0000-0000000ac001', 505.00,
          timestamptz '2026-10-23 09:00:00-07',
          '00000000-0000-0000-0000-00000000a001');

  v_est := public.aircraft_tach_estimate('00000000-0000-0000-0000-0000000ac001');
  if v_est is distinct from 505.00 then
    raise exception 'FAIL  a fresh reading left the estimate at %', v_est;
  end if;

  -- And counting resumes from the new datum.
  insert into public.flight (aircraft_id, pilot_member_id, start_at, end_at)
  values ('00000000-0000-0000-0000-0000000ac001',
          '00000000-0000-0000-0000-00000000a001',
          timestamptz '2026-10-24 10:00:00-07',
          timestamptz '2026-10-24 11:00:00-07');

  v_est := public.aircraft_tach_estimate('00000000-0000-0000-0000-0000000ac001');
  if v_est is distinct from 505.80 then
    raise exception 'FAIL  a flight after the reading estimated %', v_est;
  end if;

  raise notice 'PASS  the tach estimate runs forward from the newest reading';
end $$;
rollback;

-- ===========================================================================
-- 24. A tach entered on the Confirm screen is a reading like any other, so it
--     is mirrored into tach_reading by the database rather than by the app.
--     It is dated at the flight's END, which is what keeps a flight out of its
--     own estimate -- date it at the start and the flight would be counted on
--     top of a reading taken after it landed.
-- ===========================================================================
begin;
do $$
declare
  v_flight public.flight;
  v_read   public.tach_reading;
  v_rows   int;
  v_est    numeric;
  v_base   numeric;
begin
  -- Where the estimate stood before this test flew anything, because the only
  -- claim below is about the 0.8 hr THIS flight adds. Stated as an absolute it
  -- would be a claim about everything the seed has ever flown.
  v_base := public.aircraft_tach_estimate('00000000-0000-0000-0000-0000000ac001');

  insert into public.flight
    (aircraft_id, pilot_member_id, start_at, end_at, actual_tach_hours)
  values ('00000000-0000-0000-0000-0000000ac001',
          '00000000-0000-0000-0000-00000000a002',
          timestamptz '2026-10-09 10:00:00-07',
          timestamptz '2026-10-09 11:00:00-07',
          506.00)
  returning * into v_flight;

  select * into v_read from public.tach_reading where flight_id = v_flight.id;
  if v_read is null then
    raise exception 'FAIL  a confirmed tach produced no reading';
  end if;
  if (v_read.reading, v_read.source, v_read.read_by, v_read.read_at)
     is distinct from (506.00, 'flight'::public.tach_reading_source,
                       v_flight.pilot_member_id, v_flight.end_at) then
    raise exception 'FAIL  the flight reading is %/%/%/%',
      v_read.reading, v_read.source, v_read.read_by, v_read.read_at;
  end if;

  -- 506.0 was read AFTER this flight landed, so the flight's own 0.8 hr must
  -- not be added on top of it.
  v_est := public.aircraft_tach_estimate('00000000-0000-0000-0000-0000000ac001');
  if v_est is distinct from 506.00 then
    raise exception 'FAIL  a flight was counted inside its own reading: %', v_est;
  end if;

  -- Correcting the figure corrects the reading rather than adding a second one.
  update public.flight set actual_tach_hours = 507.00 where id = v_flight.id;
  select count(*) into v_rows from public.tach_reading where flight_id = v_flight.id;
  if v_rows <> 1 then
    raise exception 'FAIL  correcting the tach left % readings', v_rows;
  end if;
  select * into v_read from public.tach_reading where flight_id = v_flight.id;
  if v_read.reading is distinct from 507.00 then
    raise exception 'FAIL  the corrected reading says %', v_read.reading;
  end if;

  -- Taking it back takes the reading with it, so a mistake leaves no datum.
  update public.flight set actual_tach_hours = null where id = v_flight.id;
  select count(*) into v_rows from public.tach_reading where flight_id = v_flight.id;
  if v_rows <> 0 then
    raise exception 'FAIL  clearing the tach left % reading(s)', v_rows;
  end if;

  v_est := public.aircraft_tach_estimate('00000000-0000-0000-0000-0000000ac001');
  if v_est is distinct from v_base + 0.80 then
    raise exception 'FAIL  after clearing, the estimate moved by % not 0.8',
      v_est - v_base;
  end if;

  raise notice 'PASS  a confirmed tach is mirrored as a reading at the flight end';
end $$;
rollback;

-- ===========================================================================
-- 25. SPEC.md 4.4: "Marking a task done logs who, when and tach, and resets its
--     counter." Both halves are one insert, because the status view measures
--     from the newest event. Any pilot may mark a task done; only an admin may
--     move the interval, since a pilot who could shorten the grease interval
--     could also lengthen it.
-- ===========================================================================
begin;
do $$
declare
  v_left     numeric;
  v_used     numeric;
  v_state    text;
  v_rows     int;
  v_est      numeric;
  v_interval numeric;
begin
  -- The counter has run on since the grease was last done, which is the
  -- precondition for the reset below being visible at all. Asserted as "more
  -- than nothing" rather than as a figure: how much has been flown since is
  -- the seed's business, and a number here would be a claim about the seed.
  select hours_used into v_used
    from public.maintenance_status
   where id = '00000000-0000-0000-0000-0000000f0001';
  if v_used is null or v_used <= 0 then
    raise exception 'FAIL  nothing has been flown since the grease: used is %', v_used;
  end if;

  select interval_hours into v_interval
    from public.maintenance_item
   where id = '00000000-0000-0000-0000-0000000f0001';
  v_est := public.aircraft_tach_estimate('00000000-0000-0000-0000-0000000ac001');

  alter table public.member disable trigger member_guard_privileged_columns;
  update public.member set auth_user_id = null;
  alter table public.member enable trigger member_guard_privileged_columns;

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a0022",
      "email":"owner2@example.test"}', true);
  perform public.claim_member_identity();

  perform set_config('role', 'postgres', true);
  update public.member set role = 'pilot'
   where id = '00000000-0000-0000-0000-00000000a002';
  perform set_config('role', 'authenticated', true);

  -- A pilot cannot stretch the interval.
  update public.maintenance_item set interval_hours = 100.0
   where id = '00000000-0000-0000-0000-0000000f0001';
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then
    raise exception 'FAIL  a pilot moved % maintenance interval(s)', v_rows;
  end if;

  -- But can say they greased it, at the tach as it stands now.
  insert into public.maintenance_event (item_id, done_on, tach, done_by)
  values ('00000000-0000-0000-0000-0000000f0001', public.aircraft_today(), v_est,
          '00000000-0000-0000-0000-00000000a002');

  perform set_config('role', 'postgres', true);

  select hours_remaining, hours_used, state into v_left, v_used, v_state
    from public.maintenance_status
   where id = '00000000-0000-0000-0000-0000000f0001';
  if (v_left, v_used, v_state) is distinct from (v_interval, 0.00, 'ok') then
    raise exception 'FAIL  marking it done left % hr left, % used, state %',
      v_left, v_used, v_state;
  end if;

  raise notice 'PASS  any pilot can mark a task done, and only that resets it';
end $$;
rollback;

-- ===========================================================================
-- 26. Who cleared a snag, and when, are stamped by the database from the
--     session -- never taken from the request. Otherwise a crafted call could
--     record that somebody else fixed the brake.
-- ===========================================================================
begin;
do $$
declare
  v_snag public.snag;
  v_at   timestamptz;
begin
  alter table public.member disable trigger member_guard_privileged_columns;
  update public.member set auth_user_id = null;
  alter table public.member enable trigger member_guard_privileged_columns;

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a0022",
      "email":"owner2@example.test"}', true);
  perform public.claim_member_identity();

  insert into public.snag (aircraft_id, title, reported_by)
  values ('00000000-0000-0000-0000-0000000ac001', 'Test snag',
          '00000000-0000-0000-0000-00000000a002')
  returning * into v_snag;

  if v_snag.cleared_at is not null or v_snag.cleared_by is not null then
    raise exception 'FAIL  a new open snag is already cleared';
  end if;

  -- Clear it while claiming the OTHER owner did it, two years ago.
  update public.snag
     set status     = 'cleared',
         cleared_by = '00000000-0000-0000-0000-00000000a001',
         cleared_at = timestamptz '2024-01-01 00:00:00-08'
   where id = v_snag.id
  returning * into v_snag;

  if v_snag.cleared_by is distinct from '00000000-0000-0000-0000-00000000a002' then
    raise exception 'FAIL  the snag records % as having cleared it', v_snag.cleared_by;
  end if;
  if v_snag.cleared_at < now() - interval '1 minute' then
    raise exception 'FAIL  the clearing was back-dated to %', v_snag.cleared_at;
  end if;
  v_at := v_snag.cleared_at;

  -- Editing the notes afterwards must not re-stamp it.
  update public.snag set notes = 'Brake pads replaced'
   where id = v_snag.id returning * into v_snag;
  if v_snag.cleared_at is distinct from v_at then
    raise exception 'FAIL  editing the notes moved the clearing to %', v_snag.cleared_at;
  end if;

  -- Re-opening forgets it, so a reopened snag never reads as cleared by anyone.
  update public.snag set status = 'open'
   where id = v_snag.id returning * into v_snag;
  if v_snag.cleared_at is not null or v_snag.cleared_by is not null then
    raise exception 'FAIL  a reopened snag still claims it was cleared';
  end if;

  -- A grounding snag that gets cleared must stop grounding the aeroplane; the
  -- check constraint and the app agree, so assert the invariant holds.
  update public.snag set grounding = true, status = 'cleared'
   where id = v_snag.id returning * into v_snag;
  if v_snag.cleared_at is null then
    raise exception 'FAIL  clearing a grounding snag left it unstamped';
  end if;

  perform set_config('role', 'postgres', true);
  raise notice 'PASS  clearing a snag is stamped by the database, once';
end $$;
rollback;

-- ===========================================================================
-- 27. "Today" is today where the AEROPLANE is. current_date is today in the
--     database's zone, which on managed Postgres is UTC -- so from 5pm Pacific
--     onward every calendar item would quietly come due a day early. The whole
--     view must read the same day no matter what zone the caller's session is
--     in. The pair of this is AIRCRAFT_TIME_ZONE in lib/time.ts.
-- ===========================================================================
begin;
do $$
declare
  v_utc  int;
  v_nz   int;
  v_frac numeric;
begin
  set local timezone = 'UTC';
  select days_remaining, fraction_used into v_utc, v_frac
    from public.maintenance_status
   where id = '00000000-0000-0000-0000-0000000f0002';

  -- Deliberately the far side of the date line from Victoria.
  set local timezone = 'Pacific/Auckland';
  select days_remaining into v_nz
    from public.maintenance_status
   where id = '00000000-0000-0000-0000-0000000f0002';

  set local timezone = 'UTC';

  if v_utc is distinct from v_nz then
    raise exception 'FAIL  the blade clip is % days away in UTC and % in NZ',
      v_utc, v_nz;
  end if;
  if v_utc is distinct from
     (date '2026-11-22' - (now() at time zone 'America/Vancouver')::date) then
    raise exception 'FAIL  % days remaining is not measured from the aeroplane''s today',
      v_utc;
  end if;
  if v_frac is null or v_frac <= 0 or v_frac > 1 then
    raise exception 'FAIL  the blade clip bar is at %', v_frac;
  end if;

  raise notice 'PASS  maintenance due dates are measured in the aeroplane''s zone';
end $$;
rollback;

-- ===========================================================================
-- 28. The anon role must reach none of the Aircraft tab either. The tab is
--     behind a login, but the API is public, so each new table says so itself.
-- ===========================================================================
begin;
do $$
declare
  v_count int;
  v_rel   text;
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', null, true);

  -- One at a time, so a flat refusal on the first does not hide a readable
  -- table behind it. As in test 5, an outright permission error is the
  -- stronger outcome and counts as a pass; silently reading rows does not.
  foreach v_rel in array array['snag', 'tach_reading', 'maintenance_item',
                               'maintenance_event', 'maintenance_status'] loop
    begin
      execute format('select count(*) from public.%I', v_rel) into v_count;
      if v_count <> 0 then
        raise exception 'FAIL  anon read % row(s) from %', v_count, v_rel;
      end if;
    exception when insufficient_privilege then
      null;
    end;
  end loop;

  perform set_config('role', 'postgres', true);
  raise notice 'PASS  anon cannot read snags, readings or maintenance';
end $$;
rollback;

-- ===========================================================================
-- 29. "Changed oil type, check again in 10 hr" means ten hours of FLYING from
--     when it was asked for, so the tach at that moment has to be remembered.
--     Two things have to be true of that datum: the caller cannot choose it,
--     and it holds still. A datum re-stamped on every save would push the
--     re-check further away each time anyone opened the snag -- a reminder
--     that quietly never arrives.
-- ===========================================================================
begin;
do $$
declare
  v_snag public.snag;
  v_base numeric;
begin
  -- The tach as it stands, because that is what the datum must be armed
  -- against. A literal here would be a claim about how much the seed has
  -- flown, not about the trigger under test.
  v_base := public.aircraft_tach_estimate('00000000-0000-0000-0000-0000000ac001');

  -- Armed against the estimate, while claiming a datum of its own.
  insert into public.snag
    (aircraft_id, title, status, reported_by,
     recheck_tach_hours, recheck_tach_base)
  values ('00000000-0000-0000-0000-0000000ac001', 'Changed oil type', 'watch',
          '00000000-0000-0000-0000-00000000a001', 10.0, 0.00)
  returning * into v_snag;

  if v_snag.recheck_tach_base is distinct from v_base then
    raise exception 'FAIL  the re-check was armed at % rather than the tach estimate',
      v_snag.recheck_tach_base;
  end if;

  -- An hour's flying: 1/1.3 = 0.8 tach, so the re-check is now 9.2 hr away.
  insert into public.flight (aircraft_id, pilot_member_id, start_at, end_at)
  values ('00000000-0000-0000-0000-0000000ac001',
          '00000000-0000-0000-0000-00000000a001',
          timestamptz '2026-10-05 10:00:00-07',
          timestamptz '2026-10-05 11:00:00-07');

  update public.snag set notes = 'Still watching it'
   where id = v_snag.id returning * into v_snag;
  if v_snag.recheck_tach_base is distinct from v_base then
    raise exception 'FAIL  re-saving the snag moved the datum to %',
      v_snag.recheck_tach_base;
  end if;

  -- Moving the interval DOES re-arm it: twenty hours means twenty from now.
  update public.snag set recheck_tach_hours = 20.0
   where id = v_snag.id returning * into v_snag;
  if v_snag.recheck_tach_base is distinct from v_base + 0.80 then
    raise exception 'FAIL  a new interval was measured from % not the current tach',
      v_snag.recheck_tach_base;
  end if;

  -- Cancelling the re-check takes the datum with it, which is also what
  -- snag_recheck_base_needs_hours insists on.
  update public.snag set recheck_tach_hours = null
   where id = v_snag.id returning * into v_snag;
  if v_snag.recheck_tach_base is not null then
    raise exception 'FAIL  a cancelled re-check kept its datum of %',
      v_snag.recheck_tach_base;
  end if;

  -- And clearing the snag forgets the re-check entirely: a snag that is sorted
  -- has nothing left to come back to.
  update public.snag
     set recheck_item_id = '00000000-0000-0000-0000-0000000f0001'
   where id = v_snag.id;
  update public.snag set status = 'cleared'
   where id = v_snag.id returning * into v_snag;
  if v_snag.recheck_item_id is not null then
    raise exception 'FAIL  a cleared snag is still waiting on a maintenance item';
  end if;

  raise notice 'PASS  a re-check interval is measured from the tach when it was set';
end $$;
rollback;

-- ===========================================================================
-- 30. A snag answers "when should this come back?" exactly one way. Two
--     answers at once would leave every screen inventing its own precedence
--     rule. And the link is a convenience, not a dependency: retiring the job
--     a snag was waiting on must leave the snag behind, because the seep is
--     still there whether or not anyone still greases the hub.
-- ===========================================================================
begin;
do $$
declare
  v_snag    public.snag;
  v_blocked text;
  v_rows    int;
begin
  insert into public.snag
    (aircraft_id, title, status, reported_by, recheck_item_id)
  values ('00000000-0000-0000-0000-0000000ac001', 'Oil seep at valve cover',
          'watch', '00000000-0000-0000-0000-00000000a001',
          '00000000-0000-0000-0000-0000000f0001')
  returning * into v_snag;

  begin
    update public.snag set recheck_on = date '2026-12-01' where id = v_snag.id;
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a snag waits on a job AND falls due on a date';
  end if;

  begin
    update public.snag set recheck_tach_hours = 10.0 where id = v_snag.id;
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a snag waits on a job AND on a number of hours flown';
  end if;

  -- The mark-done screen's question: which live snags wait on this job?
  select count(*) into v_rows
    from public.snag s
   where s.recheck_item_id = '00000000-0000-0000-0000-0000000f0001'
     and s.status <> 'cleared'
     and s.id = v_snag.id;
  if v_rows <> 1 then
    raise exception 'FAIL  the snag waiting on the grease was not found';
  end if;

  delete from public.maintenance_item
   where id = '00000000-0000-0000-0000-0000000f0001';

  -- Counted, not re-selected into the record: a SELECT that finds nothing
  -- leaves a plpgsql record holding its previous value, so `v_snag.id is null`
  -- would never fire and the assertion would pass vacuously.
  select count(*) into v_rows from public.snag where id = v_snag.id;
  if v_rows <> 1 then
    raise exception 'FAIL  retiring the job deleted the snag waiting on it';
  end if;

  select * into v_snag from public.snag where id = v_snag.id;
  if v_snag.recheck_item_id is not null then
    raise exception 'FAIL  the snag still points at a job that no longer exists';
  end if;

  raise notice 'PASS  a snag comes back exactly one way, and outlives the job';
end $$;
rollback;

-- ===========================================================================
-- 31. month_charges() is the only arithmetic for what a month costs: the Bills
--     screen's live draft and close_month() both ask it, so the review step
--     cannot disagree with the invoice it is reviewing. Two things have to hold
--     of it. It is security definer, so it must refuse to price somebody else's
--     month unless an admin is asking -- SPEC.md 4.6, "only an admin sees all
--     pilots' numbers". And it must repeat the month's hours on every component
--     line, because that is what lets the Bills screen show the one wet rate
--     SPEC.md 4.8 promises without a second query inventing its own hours.
-- ===========================================================================
begin;
do $$
declare
  v_aircraft uuid := '00000000-0000-0000-0000-0000000ac001';
  v_one      uuid := '00000000-0000-0000-0000-00000000a001';
  v_two      uuid := '00000000-0000-0000-0000-00000000a002';
  -- April, a month the seed does not touch. Every figure below is then this
  -- test's own doing rather than a restatement of the seed, which is what went
  -- wrong with the absolutes elsewhere in this file.
  v_month    date := date '2026-04-01';
  v_rows     int;
  v_distinct int;
  v_hours    numeric;
  v_total    numeric;
  v_qty      numeric;
  v_desc     text;
  v_blocked  text;
begin
  insert into public.flight
    (aircraft_id, pilot_member_id, status, start_at, end_at)
  values (v_aircraft, v_one, 'confirmed',
          timestamptz '2026-04-10 10:00 America/Vancouver',
          timestamptz '2026-04-10 11:24 America/Vancouver');

  -- Both owners claim their row through the real path. The arithmetic below is
  -- read as the admin, because month_charges has no answer at all for a caller
  -- with no session -- which is the first thing this test establishes.
  alter table public.member disable trigger member_guard_privileged_columns;
  update public.member set auth_user_id = null;
  alter table public.member enable trigger member_guard_privileged_columns;

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a0311",
      "email":"owner1@example.test"}', true);
  perform public.claim_member_identity();
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a0312",
      "email":"owner2@example.test"}', true);
  perform public.claim_member_identity();

  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a0311"}', true);

  -- 1.4 hr across the opening rate's six components.
  select count(*), count(distinct period_hours), max(period_hours), sum(amount)
    into v_rows, v_distinct, v_hours, v_total
  from public.month_charges(v_aircraft, v_one, v_month)
  where kind = 'flight_charge';

  if v_rows <> 6 then
    raise exception 'FAIL  the flight priced as % component lines, not 6', v_rows;
  end if;
  if (v_distinct, v_hours) is distinct from (1, 1.4) then
    raise exception 'FAIL  the component lines carry % different hours, highest %',
      v_distinct, v_hours;
  end if;
  if v_total is distinct from 399.00 then
    raise exception 'FAIL  1.4 hr at the opening rate came to %, not 1.4 x 285', v_total;
  end if;

  -- Plus half of each monthly fixed cost, because this company splits them by
  -- ownership percent and the two owners are 50/50.
  select sum(amount), max(quantity), min(description)
    into v_total, v_qty, v_desc
  from public.month_charges(v_aircraft, v_one, v_month)
  where kind <> 'flight_charge';

  if (v_total, v_qty) is distinct from (525.00, 0.5) then
    raise exception 'FAIL  the fixed costs came to % at a share of %', v_total, v_qty;
  end if;
  -- The share is named in the description, which is why the Bills screen shows
  -- those lines without a caption of their own.
  if v_desc not like '%50% share%' then
    raise exception 'FAIL  a fixed cost line reads "%"', v_desc;
  end if;

  -- Nothing is charged while the company is not GST registered, which it is
  -- not until SPEC.md section 8 question 5 is answered.
  select sum(gst_amount) into v_total
  from public.month_charges(v_aircraft, v_one, v_month);
  if v_total is distinct from 0 then
    raise exception 'FAIL  GST of % was charged by an unregistered company', v_total;
  end if;

  -- Now the authorisation. A pilot may price their own month and nobody
  -- else's; the refusal is the only thing standing between security definer
  -- and every pilot reading every other pilot's figures.
  perform set_config('role', 'postgres', true);
  update public.member set role = 'pilot' where id = v_two;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a0312"}', true);

  begin
    perform * from public.month_charges(v_aircraft, v_one, v_month);
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a pilot priced another owner''s month';
  end if;

  -- And the other half of the claim, so the refusal above is about whose month
  -- it is rather than a blanket block.
  select count(*) into v_rows
  from public.month_charges(v_aircraft, v_two, v_month);
  if v_rows <> 2 then
    raise exception 'FAIL  a pilot got % lines for their own month', v_rows;
  end if;

  raise notice 'PASS  a month is priced once, and only an admin prices anyone else''s';
end $$;
rollback;

-- ===========================================================================
-- 32. The owners' rule, 13 Oct 2026: a payment is recorded by an admin OTHER
--     than the member it credits, whenever there is another admin to ask. Both
--     owners are admins, so "admin only" on its own would let either of them
--     clear their own balance unseen. Two layers have to hold: recorded_by is
--     stamped from the session so it cannot be claimed, and the guard reads
--     that stamp rather than anything in the request.
--
--     The rule stands down when there is only one admin -- the first weeks, or
--     after a departure. A rule that locked the only admin out of recording a
--     payment would just mean the ledger stopped being true.
-- ===========================================================================
begin;
do $$
declare
  v_company uuid := '00000000-0000-0000-0000-00000000c000';
  v_one     uuid := '00000000-0000-0000-0000-00000000a001';
  v_two     uuid := '00000000-0000-0000-0000-00000000a002';
  v_entry   uuid;
  v_who     uuid;
  v_amount  numeric;
  v_blocked text;
begin
  alter table public.member disable trigger member_guard_privileged_columns;
  update public.member set auth_user_id = null;
  alter table public.member enable trigger member_guard_privileged_columns;

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a0032",
      "email":"owner1@example.test"}', true);
  perform public.claim_member_identity();

  -- Recording somebody else's payment is the honest case, and the stamp
  -- overrides what the request asked for: a caller cannot put the other
  -- admin's name on a row they entered themselves.
  insert into public.ledger_entry
    (company_id, member_id, kind, entry_date, description, amount,
     tax_treatment, gl_account_code, recorded_by)
  values (v_company, v_two, 'payment', date '2026-04-05', 'e-Transfer',
          -100.00, 'out_of_scope', '1000', v_two)
  returning recorded_by into v_who;
  if v_who is distinct from v_one then
    raise exception 'FAIL  the row was recorded by % rather than the session', v_who;
  end if;

  -- So the guard cannot be walked around by claiming the other admin did it.
  begin
    insert into public.ledger_entry
      (company_id, member_id, kind, entry_date, description, amount,
       tax_treatment, gl_account_code, recorded_by)
    values (v_company, v_one, 'payment', date '2026-04-05', 'e-Transfer',
            -100.00, 'out_of_scope', '1000', v_two);
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  an admin cleared their own balance under another name';
  end if;

  -- Money going the other way is the same conflict of interest.
  begin
    insert into public.ledger_entry
      (company_id, member_id, kind, entry_date, description, amount,
       tax_treatment, gl_account_code)
    values (v_company, v_one, 'payout', date '2026-04-05', 'Distribution',
            100.00, 'out_of_scope', '1000');
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  an admin paid themselves out unwitnessed';
  end if;

  -- Through the function the app actually calls, too.
  begin
    perform public.record_payment(v_one, 500.00, date '2026-04-05');
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  record_payment credited the caller''s own balance';
  end if;

  -- The amount is typed in as the positive figure on the bank statement and
  -- stored negative, because in this ledger positive means the member owes
  -- more. The caller should not have to think about the sign convention.
  v_entry := public.record_payment(v_two, 500.00, date '2026-04-06', '  ref 4821 ');
  select amount, recorded_by, description into v_amount, v_who, v_blocked
  from public.ledger_entry where id = v_entry;
  if (v_amount, v_who, v_blocked) is distinct from (-500.00, v_one, 'ref 4821') then
    raise exception 'FAIL  the payment stored %/%/%', v_amount, v_who, v_blocked;
  end if;

  -- And with nobody else to ask, the rule stands down.
  perform set_config('role', 'postgres', true);
  update public.member set role = 'pilot' where id = v_two;
  perform set_config('role', 'authenticated', true);

  v_entry := public.record_payment(v_one, 500.00, date '2026-04-07');
  if v_entry is null then
    raise exception 'FAIL  the only admin could not record their own payment';
  end if;

  raise notice 'PASS  a payment is witnessed by another admin whenever there is one';
end $$;
rollback;

-- ===========================================================================
-- 33. SPEC.md 4.6: "Closing a month locks that month's flights and generates
--     the invoice", and "a sent invoice never changes silently". Closing is
--     therefore deliberately re-runnable while the invoice is a draft -- an
--     admin who spots a wrong flight time fixes it and closes again -- and
--     deliberately inert once it is issued. The dangerous failure is the one
--     in between: a second close that ADDS a second set of lines rather than
--     replacing the first, which reads as a month billed twice.
-- ===========================================================================
begin;
do $$
declare
  v_aircraft uuid := '00000000-0000-0000-0000-0000000ac001';
  v_one      uuid := '00000000-0000-0000-0000-00000000a001';
  v_month    date := date '2026-04-01';
  v_invoice  uuid;
  v_status   public.invoice_status;
  v_number   bigint;
  v_built    int;
  v_rows     int;
  v_total    numeric;
  v_blocked  text;
begin
  insert into public.flight
    (aircraft_id, pilot_member_id, status, start_at, end_at)
  values (v_aircraft, v_one, 'confirmed',
          timestamptz '2026-04-10 10:00 America/Vancouver',
          timestamptz '2026-04-10 11:24 America/Vancouver');

  alter table public.member disable trigger member_guard_privileged_columns;
  update public.member set auth_user_id = null;
  alter table public.member enable trigger member_guard_privileged_columns;

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a0033",
      "email":"owner1@example.test"}', true);
  perform public.claim_member_identity();

  -- Both owners: one flew, and both owe their share of the hangar.
  v_built := public.close_month(v_aircraft, v_month);
  if v_built <> 2 then
    raise exception 'FAIL  closing April built % drafts, not one per owner', v_built;
  end if;

  select id into v_invoice from public.invoice
   where member_id = v_one and period_month = v_month;
  select count(*), public.invoice_total(v_invoice) into v_rows, v_total
  from public.ledger_entry where invoice_id = v_invoice;
  if (v_rows, v_total) is distinct from (8, 924.00) then
    raise exception 'FAIL  the draft has % lines coming to %', v_rows, v_total;
  end if;

  -- The charge belongs to the month it was incurred in, whenever the admin got
  -- round to closing it.
  select count(*) into v_rows from public.ledger_entry
   where invoice_id = v_invoice and entry_date <> date '2026-04-30';
  if v_rows <> 0 then
    raise exception 'FAIL  % line(s) are not dated the end of the month they cover', v_rows;
  end if;

  -- Correct the flight and close again: the same invoice, re-priced, not a
  -- second one and not sixteen lines.
  perform set_config('role', 'postgres', true);
  update public.flight set end_at = timestamptz '2026-04-10 11:54 America/Vancouver'
   where pilot_member_id = v_one and public.aircraft_date(start_at) = date '2026-04-10';
  perform set_config('role', 'authenticated', true);

  v_built := public.close_month(v_aircraft, v_month);
  select count(*) into v_rows from public.invoice
   where member_id = v_one and period_month = v_month;
  if (v_built, v_rows) is distinct from (2, 1) then
    raise exception 'FAIL  closing twice built % drafts over % invoice(s)', v_built, v_rows;
  end if;
  select count(*), public.invoice_total(v_invoice) into v_rows, v_total
  from public.ledger_entry where invoice_id = v_invoice;
  if (v_rows, v_total) is distinct from (8, 1066.50) then
    raise exception 'FAIL  the rebuilt draft has % lines coming to %', v_rows, v_total;
  end if;

  -- Issued, it is the record of what was sent. Closing again must step over it
  -- entirely -- and the figure proves it did, because the flights are locked
  -- now, so a rebuild would come back as the fixed costs alone.
  v_number := public.issue_invoice(v_invoice);
  v_built  := public.close_month(v_aircraft, v_month);
  if v_built <> 1 then
    raise exception 'FAIL  closing again rebuilt % drafts, not just the open one', v_built;
  end if;

  select status, number into v_status, v_number from public.invoice where id = v_invoice;
  if (v_status, public.invoice_total(v_invoice)) is distinct from ('issued', 1066.50) then
    raise exception 'FAIL  the issued invoice is now % at %',
      v_status, public.invoice_total(v_invoice);
  end if;
  if v_number is null then
    raise exception 'FAIL  the issued invoice lost its number';
  end if;

  -- A month nobody owned the aeroplane in produces no invoices at all, rather
  -- than $0.00 ones to ignore.
  v_built := public.close_month(v_aircraft, date '2025-12-01');
  select count(*) into v_rows from public.invoice where period_month = date '2025-12-01';
  if (v_built, v_rows) is distinct from (0, 0) then
    raise exception 'FAIL  an empty month built % drafts and left % invoice(s)',
      v_built, v_rows;
  end if;

  -- The future is not closeable: there is still flying to come.
  begin
    perform public.close_month(
      v_aircraft,
      (date_trunc('month', public.aircraft_today()) + interval '2 months')::date);
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a month that has not started yet was closed';
  end if;

  -- And a pilot cannot close one. The Server Action checks this too, but a
  -- Server Action is a public POST endpoint, so it is the belt and this is the
  -- braces. Note when mutation-testing this one that it holds in two layers:
  -- removing close_month's own role check is not enough, because month_charges
  -- then refuses to price the other owner's month anyway.
  perform set_config('role', 'postgres', true);
  update public.member set role = 'pilot' where id = v_one;
  perform set_config('role', 'authenticated', true);
  begin
    perform public.close_month(v_aircraft, v_month);
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a pilot closed the month';
  end if;

  raise notice 'PASS  a draft rebuilds on every close, and an issued invoice never does';
end $$;
rollback;

-- ===========================================================================
-- 34. Issuing is the irreversible half. The number is allocated here rather
--     than at draft time because a discarded draft would leave a gap, and a
--     GST invoice run must not have one. And the lock has to cover exactly the
--     flights that were priced: anything narrower bills a flight twice next
--     month, anything wider swallows one that was never charged for. Both
--     sides ask month_flight_ids() which flights those are, so this test holds
--     the answer still and checks the lock against it.
-- ===========================================================================
begin;
do $$
declare
  v_aircraft uuid := '00000000-0000-0000-0000-0000000ac001';
  v_company  uuid := '00000000-0000-0000-0000-00000000c000';
  v_one      uuid := '00000000-0000-0000-0000-00000000a001';
  v_two      uuid := '00000000-0000-0000-0000-00000000a002';
  v_month    date := date '2026-04-01';
  v_mine     uuid;
  v_theirs   uuid;
  v_empty    uuid;
  v_ids      uuid[];
  v_before   bigint;
  v_after    bigint;
  v_first    bigint;
  v_second   bigint;
  v_rows     int;
  v_blocked  text;
begin
  insert into public.flight
    (aircraft_id, pilot_member_id, status, start_at, end_at)
  values (v_aircraft, v_one, 'confirmed',
          timestamptz '2026-04-10 10:00 America/Vancouver',
          timestamptz '2026-04-10 11:24 America/Vancouver'),
         (v_aircraft, v_two, 'confirmed',
          timestamptz '2026-04-12 13:00 America/Vancouver',
          timestamptz '2026-04-12 13:36 America/Vancouver');

  -- A draft with nothing on it, to be refused below.
  insert into public.invoice (company_id, member_id, period_month)
  values (v_company, v_one, date '2026-03-01')
  returning id into v_empty;

  select next_number into v_before
  from public.invoice_counter where company_id = v_company;

  alter table public.member disable trigger member_guard_privileged_columns;
  update public.member set auth_user_id = null;
  alter table public.member enable trigger member_guard_privileged_columns;

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a0034",
      "email":"owner1@example.test"}', true);
  perform public.claim_member_identity();

  perform public.close_month(v_aircraft, v_month);
  select id into v_mine   from public.invoice
   where member_id = v_one and period_month = v_month;
  select id into v_theirs from public.invoice
   where member_id = v_two and period_month = v_month;

  -- Held still before issuing, because issuing is what takes these flights out
  -- of month_flight_ids' answer.
  select array_agg(t.flight_id) into v_ids
  from public.month_flight_ids(v_aircraft, v_one, v_month) as t(flight_id);
  if coalesce(array_length(v_ids, 1), 0) <> 1 then
    raise exception 'FAIL  the month named % flights to lock, so the test proves nothing',
      coalesce(array_length(v_ids, 1), 0);
  end if;

  -- An empty draft would take a number and say nothing.
  begin
    perform public.issue_invoice(v_empty);
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  an invoice with no lines was issued';
  end if;

  v_first  := public.issue_invoice(v_mine);
  v_second := public.issue_invoice(v_theirs);

  -- Read back as postgres: the counter has no select policy at all, because
  -- nothing is meant to read it except next_invoice_number(), which is
  -- security definer. Asking as the admin would silently return null.
  perform set_config('role', 'postgres', true);
  select next_number into v_after
  from public.invoice_counter where company_id = v_company;
  perform set_config('role', 'authenticated', true);

  -- Gapless, and stated as "the next one, then the one after" rather than as
  -- figures: which numbers they are is the seed's business.
  if (v_first, v_second, v_after) is distinct from (v_before, v_before + 1, v_before + 2) then
    raise exception 'FAIL  numbering went % then % with the counter at %, from %',
      v_first, v_second, v_after, v_before;
  end if;

  -- Every flight that was priced is locked to the invoice that priced it.
  select count(*) into v_rows from public.flight
   where id = any(v_ids)
     and (status <> 'billed' or invoice_id is distinct from v_mine);
  if v_rows <> 0 then
    raise exception 'FAIL  % of the month''s flights were left unlocked', v_rows;
  end if;

  -- And nothing else is, so the lock did not reach into another month or
  -- another pilot's flying.
  select count(*) into v_rows from public.flight
   where invoice_id = v_mine and not (id = any(v_ids));
  if v_rows <> 0 then
    raise exception 'FAIL  % flight(s) outside the month were locked to the invoice', v_rows;
  end if;

  -- Issuing twice would allocate a second number to the same invoice. Two
  -- layers again: removing issue_invoice's own status check is not enough,
  -- because invoice_guard_immutable refuses the update either way.
  begin
    perform public.issue_invoice(v_mine);
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  an issued invoice was issued again';
  end if;

  perform set_config('role', 'postgres', true);
  update public.member set role = 'pilot' where id = v_one;
  perform set_config('role', 'authenticated', true);
  begin
    perform public.issue_invoice(v_empty);
    v_blocked := null;
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked is null then
    raise exception 'FAIL  a pilot issued an invoice';
  end if;

  raise notice 'PASS  issuing takes the next number and locks exactly the month priced';
end $$;
rollback;

-- ===========================================================================
-- 35. All three arms of fixed_cost_split are implemented even though this
--     company uses ownership_pct, because a setting that silently bills the
--     wrong split when flipped is worse than no setting at all. Nobody will
--     exercise the other two by hand before the day they are switched on.
--
--     The share is read as of the FIRST of the month throughout: a hangarage
--     rise or an ownership change on the 20th applies to the next bill, not
--     retroactively to this one.
-- ===========================================================================
begin;
do $$
declare
  v_aircraft uuid := '00000000-0000-0000-0000-0000000ac001';
  v_one      uuid := '00000000-0000-0000-0000-00000000a001';
  v_two      uuid := '00000000-0000-0000-0000-00000000a002';
  v_month    date := date '2026-04-01';
begin
  -- ownership_pct: the two owners are 50/50 from 1 Jan.
  if public.fixed_cost_share(v_aircraft, v_one, v_month) is distinct from 0.5 then
    raise exception 'FAIL  a 50%% owner''s share of the hangar is %',
      public.fixed_cost_share(v_aircraft, v_one, v_month);
  end if;

  -- Before anyone owned it, nobody pays for it. Returned as 0 rather than
  -- null, so close_month writes no line instead of a null one.
  if public.fixed_cost_share(v_aircraft, v_one, date '2025-12-01') is distinct from 0 then
    raise exception 'FAIL  a month before the ownership began charges a share of %',
      public.fixed_cost_share(v_aircraft, v_one, date '2025-12-01');
  end if;

  -- An ownership change part-way through the month belongs to the NEXT bill:
  -- the share is read as of the first, whatever date it is asked about. Only
  -- the mid-month question can catch this, because asking about the 1st gives
  -- the same answer whether or not the date is truncated.
  insert into public.ownership_period (id, aircraft_id, effective_from, note)
  values ('00000000-0000-0000-0000-0000000b0351', v_aircraft, date '2026-04-20',
          'A change part-way through April');
  insert into public.ownership_share (period_id, member_id, pct) values
    ('00000000-0000-0000-0000-0000000b0351', v_one, 100.0000),
    ('00000000-0000-0000-0000-0000000b0351', v_two,   0.0000);

  if public.fixed_cost_share(v_aircraft, v_one, date '2026-04-20') is distinct from 0.5 then
    raise exception 'FAIL  asked about the 20th, April''s share is %',
      public.fixed_cost_share(v_aircraft, v_one, date '2026-04-20');
  end if;

  -- equal: the same answer here, which is the point -- 50/50 ownership and two
  -- owners sharing equally are the same split, so this arm is pinned by the
  -- case below it rather than by this one.
  update public.aircraft set fixed_cost_split = 'equal' where id = v_aircraft;
  if public.fixed_cost_share(v_aircraft, v_one, v_month) is distinct from 0.5 then
    raise exception 'FAIL  one of two equal owners pays %',
      public.fixed_cost_share(v_aircraft, v_one, v_month);
  end if;

  -- An owner who has exited sits at 0% and does not pay hangarage, so "equal"
  -- means equal among the owners of record that month and not among everyone
  -- still on the roster.
  insert into public.ownership_period (id, aircraft_id, effective_from, note)
  values ('00000000-0000-0000-0000-0000000b0035', v_aircraft, date '2026-03-01',
          'One owner bought the other out');
  insert into public.ownership_share (period_id, member_id, pct) values
    ('00000000-0000-0000-0000-0000000b0035', v_one, 100.0000),
    ('00000000-0000-0000-0000-0000000b0035', v_two,   0.0000);

  if public.fixed_cost_share(v_aircraft, v_one, v_month) is distinct from 1.0 then
    raise exception 'FAIL  the sole remaining owner pays %',
      public.fixed_cost_share(v_aircraft, v_one, v_month);
  end if;
  if public.fixed_cost_share(v_aircraft, v_two, v_month) is distinct from 0 then
    raise exception 'FAIL  an exited owner still pays %',
      public.fixed_cost_share(v_aircraft, v_two, v_month);
  end if;

  -- hours_flown: whoever flew it pays for the hangar it sat in, in proportion.
  -- 1.4 hr against 0.6 hr is 70/30, and ownership is irrelevant to this arm --
  -- which the period inserted above proves, since it would say 100/0.
  update public.aircraft set fixed_cost_split = 'hours_flown' where id = v_aircraft;
  insert into public.flight
    (aircraft_id, pilot_member_id, status, start_at, end_at)
  values (v_aircraft, v_one, 'confirmed',
          timestamptz '2026-04-10 10:00 America/Vancouver',
          timestamptz '2026-04-10 11:24 America/Vancouver'),
         (v_aircraft, v_two, 'confirmed',
          timestamptz '2026-04-12 13:00 America/Vancouver',
          timestamptz '2026-04-12 13:36 America/Vancouver');

  if public.fixed_cost_share(v_aircraft, v_one, v_month) is distinct from 0.7 then
    raise exception 'FAIL  1.4 of 2.0 hr flown is a share of %',
      public.fixed_cost_share(v_aircraft, v_one, v_month);
  end if;
  if public.fixed_cost_share(v_aircraft, v_two, v_month) is distinct from 0.3 then
    raise exception 'FAIL  0.6 of 2.0 hr flown is a share of %',
      public.fixed_cost_share(v_aircraft, v_two, v_month);
  end if;

  -- A month nobody flew divides by zero unless it is guarded.
  if public.fixed_cost_share(v_aircraft, v_one, date '2026-02-01') is distinct from 0 then
    raise exception 'FAIL  a month with no flying gives a share of %',
      public.fixed_cost_share(v_aircraft, v_one, date '2026-02-01');
  end if;

  raise notice 'PASS  every fixed-cost split is implemented, and reads as of the 1st';
end $$;
rollback;

-- ===========================================================================
-- 36. Settling is a convenience, not an accounting fact -- the balance is the
--     sum of the ledger either way. So it is all-or-nothing against the whole
--     balance rather than an allocation of one payment to particular invoices,
--     which would need a matching table and would still be guesswork. What
--     must not happen is a part payment marking the bill Paid.
-- ===========================================================================
begin;
do $$
declare
  v_one     uuid := '00000000-0000-0000-0000-00000000a001';
  v_owed    numeric;
  v_part    numeric;
  v_due     int;
  v_rows    int;
begin
  -- Measured from the ledger rather than stated, because what the seed has
  -- billed and paid is the seed's business.
  v_owed := public.member_balance(v_one);
  select count(*) into v_due from public.invoice
   where member_id = v_one and status = 'issued';
  if v_owed <= 0 or v_due = 0 then
    raise exception 'FAIL  nothing is outstanding, so the test proves nothing: % over % invoice(s)',
      v_owed, v_due;
  end if;

  alter table public.member disable trigger member_guard_privileged_columns;
  update public.member set auth_user_id = null;
  alter table public.member enable trigger member_guard_privileged_columns;

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-0000000a0036",
      "email":"owner2@example.test"}', true);
  perform public.claim_member_identity();

  -- Half of it, recorded by the other admin as the rule requires.
  v_part := round(v_owed / 2, 2);
  perform public.record_payment(v_one, v_part, date '2026-10-20');

  perform set_config('role', 'postgres', true);
  select count(*) into v_rows from public.invoice
   where member_id = v_one and status = 'issued';
  if v_rows <> v_due then
    raise exception 'FAIL  a part payment settled % of % due invoice(s)',
      v_due - v_rows, v_due;
  end if;
  if public.member_balance(v_one) is distinct from v_owed - v_part then
    raise exception 'FAIL  after paying % the balance is % not %',
      v_part, public.member_balance(v_one), v_owed - v_part;
  end if;

  -- And now the rest.
  perform set_config('role', 'authenticated', true);
  perform public.record_payment(v_one, v_owed - v_part, date '2026-10-21');

  perform set_config('role', 'postgres', true);
  if public.member_balance(v_one) is distinct from 0 then
    raise exception 'FAIL  paying the balance in full left %',
      public.member_balance(v_one);
  end if;
  select count(*) into v_rows from public.invoice
   where member_id = v_one and status = 'issued';
  if v_rows <> 0 then
    raise exception 'FAIL  % invoice(s) stayed due after the balance cleared', v_rows;
  end if;
  select count(*) into v_rows from public.invoice
   where member_id = v_one and status = 'settled' and settled_at is null;
  if v_rows <> 0 then
    raise exception 'FAIL  % settled invoice(s) do not say when', v_rows;
  end if;

  raise notice 'PASS  only a payment that clears the balance settles the invoices';
end $$;
rollback;

-- ===========================================================================
-- 37. A bill is for a calendar month at the aircraft's base. Bucketing flights
--     by the raw timestamp would be bucketing them by UTC, which after 5pm in
--     Victoria is already tomorrow -- so the last evening of the month would
--     land on the next month's bill, and the last afternoon of the month
--     before would land on this one. Both directions are checked, because the
--     bug is symmetrical and only one half of it is obvious.
-- ===========================================================================
begin;
do $$
declare
  v_aircraft uuid := '00000000-0000-0000-0000-0000000ac001';
  v_one      uuid := '00000000-0000-0000-0000-00000000a001';
  v_evening  uuid;
  v_eve_prev uuid;
  v_rows     int;
begin
  -- 18:00 on 30 April in Victoria is 01:00 on 1 May in UTC.
  insert into public.flight
    (aircraft_id, pilot_member_id, status, start_at, end_at)
  values (v_aircraft, v_one, 'confirmed',
          timestamptz '2026-04-30 18:00 America/Vancouver',
          timestamptz '2026-04-30 19:00 America/Vancouver')
  returning id into v_evening;

  -- And 17:00 on 31 March is midnight on 1 April, which the same mistake
  -- pushes the other way.
  insert into public.flight
    (aircraft_id, pilot_member_id, status, start_at, end_at)
  values (v_aircraft, v_one, 'confirmed',
          timestamptz '2026-03-31 17:00 America/Vancouver',
          timestamptz '2026-03-31 18:00 America/Vancouver')
  returning id into v_eve_prev;

  if public.aircraft_date(timestamptz '2026-04-30 18:00 America/Vancouver')
     is distinct from date '2026-04-30' then
    raise exception 'FAIL  an evening in Victoria is dated %',
      public.aircraft_date(timestamptz '2026-04-30 18:00 America/Vancouver');
  end if;

  select count(*) into v_rows
  from public.month_flight_ids(v_aircraft, v_one, date '2026-04-01') as t(flight_id)
  where t.flight_id = v_evening;
  if v_rows <> 1 then
    raise exception 'FAIL  an evening flight on the 30th is not on April''s bill';
  end if;

  select count(*) into v_rows
  from public.month_flight_ids(v_aircraft, v_one, date '2026-05-01') as t(flight_id)
  where t.flight_id = v_evening;
  if v_rows <> 0 then
    raise exception 'FAIL  an evening flight on 30 April is billed in May as well';
  end if;

  select count(*) into v_rows
  from public.month_flight_ids(v_aircraft, v_one, date '2026-04-01') as t(flight_id)
  where t.flight_id = v_eve_prev;
  if v_rows <> 0 then
    raise exception 'FAIL  an evening flight on 31 March is billed in April';
  end if;

  select count(*) into v_rows
  from public.month_flight_ids(v_aircraft, v_one, date '2026-03-01') as t(flight_id)
  where t.flight_id = v_eve_prev;
  if v_rows <> 1 then
    raise exception 'FAIL  an evening flight on 31 March is not on March''s bill';
  end if;

  raise notice 'PASS  a month is billed as the aeroplane''s calendar month';
end $$;
rollback;

\echo ''
\echo 'All core schema checks passed.'
