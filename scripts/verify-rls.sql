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

\echo ''
\echo 'All core schema checks passed.'
