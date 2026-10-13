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

do $$
declare
  v_balance numeric;
  v_total   numeric;
begin
  v_balance := public.member_balance('00000000-0000-0000-0000-00000000a001');
  v_total   := public.invoice_total('00000000-0000-0000-0000-00000000f001');

  if v_balance <> 0 then
    raise exception 'FAIL  a draft invoice moved the balance to %', v_balance;
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
  if v_balance <> 997.50 then
    raise exception 'FAIL  issuing left the balance at %', v_balance;
  end if;

  update public.invoice set status = 'void'
   where id = '00000000-0000-0000-0000-00000000f001';

  v_balance := public.member_balance('00000000-0000-0000-0000-00000000a001');
  if v_balance <> 0 then
    raise exception 'FAIL  a void invoice still owes %', v_balance;
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

  -- Count and ownership both, because a count of one row proves nothing on its
  -- own about which row it is.
  select count(*), count(*) filter (
           where member_id = '00000000-0000-0000-0000-00000000a002')
    into v_entries, v_own
  from public.ledger_entry;
  select count(*) into v_posted   from public.ledger_entry_posted;
  select count(*) into v_journal  from public.gl_journal;
  select count(*) into v_invoices from public.invoice;
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

  if v_entries <> 1 or v_own <> 1 then
    raise exception 'FAIL  a pilot read % ledger entries, % of them their own',
      v_entries, v_own;
  end if;
  if v_posted <> 1 then
    raise exception 'FAIL  a pilot read % rows through ledger_entry_posted', v_posted;
  end if;
  -- Two journal lines per entry, so one entry is two rows.
  if v_journal <> 2 then
    raise exception 'FAIL  a pilot read % rows through gl_journal', v_journal;
  end if;
  if v_invoices <> 1 then
    raise exception 'FAIL  a pilot read % invoices', v_invoices;
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
        date '2026-09-01', 'issued', 9201, now());

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
            'flight_charge', date '2026-09-10', 'Wrong owner', 285.00, '4100');
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
        date '2026-10-01', 'issued', 9301, now());

insert into public.ledger_entry
  (company_id, member_id, invoice_id, kind, entry_date, description,
   amount, gl_account_code) values
  ('00000000-0000-0000-0000-00000000c000', '00000000-0000-0000-0000-00000000a001',
   '00000000-0000-0000-0000-00000000f006', 'flight_charge', date '2026-10-05',
   '2.0 hr x $285.00', 570.00, '4100'),
  ('00000000-0000-0000-0000-00000000c000', '00000000-0000-0000-0000-00000000a001',
   null, 'payment', date '2026-10-20', 'e-Transfer received', -570.00, '1000');

do $$
declare
  v_net    numeric;
  v_rows   int;
  v_ar     numeric;
  v_bank   numeric;
begin
  select coalesce(sum(debit_credit), 0), count(*) into v_net, v_rows
  from public.gl_journal
  where entry_date between date '2026-10-01' and date '2026-10-31';

  if v_net <> 0 then
    raise exception 'FAIL  the journal nets to % over October', v_net;
  end if;
  if v_rows <> 4 then
    raise exception 'FAIL  two entries produced % journal lines', v_rows;
  end if;

  -- The charge debits receivables; the payment credits them and debits the bank.
  select coalesce(sum(debit_credit), 0) into v_ar
  from public.gl_journal
  where gl_account_code = '1100' and entry_date >= date '2026-10-01';
  select coalesce(sum(debit_credit), 0) into v_bank
  from public.gl_journal
  where gl_account_code = '1000' and entry_date >= date '2026-10-01';

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
  v_a     public.flight;
  v_b     public.flight;
  v_count int;
begin
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
  if v_count <> 1 then
    raise exception 'FAIL  four calls left % flights', v_count;
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
  v_est := public.aircraft_tach_estimate('00000000-0000-0000-0000-0000000ac001');
  if v_est is distinct from 500.00 then
    raise exception 'FAIL  with no flights the estimate is % not the reading', v_est;
  end if;

  -- Two one-hour flights after the reading: 1/1.3 = 0.769 -> 0.8 tach each.
  insert into public.flight (aircraft_id, pilot_member_id, start_at, end_at)
  values ('00000000-0000-0000-0000-0000000ac001',
          '00000000-0000-0000-0000-00000000a001',
          timestamptz '2026-10-05 10:00:00-07',
          timestamptz '2026-10-05 11:00:00-07'),
         ('00000000-0000-0000-0000-0000000ac001',
          '00000000-0000-0000-0000-00000000a001',
          timestamptz '2026-10-06 10:00:00-07',
          timestamptz '2026-10-06 11:00:00-07');

  v_est := public.aircraft_tach_estimate('00000000-0000-0000-0000-0000000ac001');
  if v_est is distinct from 501.60 then
    raise exception 'FAIL  two 0.8 hr flights estimated the tach at %', v_est;
  end if;

  -- The meter actually says 505.0. Nothing is reset by hand; the new reading
  -- is simply newer, so the two flights above are now behind it.
  insert into public.tach_reading (aircraft_id, reading, read_at, read_by)
  values ('00000000-0000-0000-0000-0000000ac001', 505.00,
          timestamptz '2026-10-07 09:00:00-07',
          '00000000-0000-0000-0000-00000000a001');

  v_est := public.aircraft_tach_estimate('00000000-0000-0000-0000-0000000ac001');
  if v_est is distinct from 505.00 then
    raise exception 'FAIL  a fresh reading left the estimate at %', v_est;
  end if;

  -- And counting resumes from the new datum.
  insert into public.flight (aircraft_id, pilot_member_id, start_at, end_at)
  values ('00000000-0000-0000-0000-0000000ac001',
          '00000000-0000-0000-0000-00000000a001',
          timestamptz '2026-10-08 10:00:00-07',
          timestamptz '2026-10-08 11:00:00-07');

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
begin
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
  if v_est is distinct from 500.80 then
    raise exception 'FAIL  after clearing, the estimate is % not seed + 0.8', v_est;
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
  v_left  numeric;
  v_used  numeric;
  v_state text;
  v_rows  int;
begin
  select hours_remaining, hours_used, state into v_left, v_used, v_state
    from public.maintenance_status
   where id = '00000000-0000-0000-0000-0000000f0001';
  if (v_left, v_used, v_state) is distinct from (6.00, 19.00, 'ok') then
    raise exception 'FAIL  the seeded grease reads %/%/%', v_left, v_used, v_state;
  end if;

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

  -- But can say they greased it.
  insert into public.maintenance_event (item_id, done_on, tach, done_by)
  values ('00000000-0000-0000-0000-0000000f0001', date '2026-10-11', 500.00,
          '00000000-0000-0000-0000-00000000a002');

  perform set_config('role', 'postgres', true);

  select hours_remaining, hours_used into v_left, v_used
    from public.maintenance_status
   where id = '00000000-0000-0000-0000-0000000f0001';
  if (v_left, v_used) is distinct from (25.00, 0.00) then
    raise exception 'FAIL  marking it done left % hr left, % used', v_left, v_used;
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

\echo ''
\echo 'All core schema checks passed.'
