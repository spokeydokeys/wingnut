-- Closing a month, and taking the money.
--
-- The ledger migration built the shapes. This one builds the single arithmetic
-- that fills them, and it is deliberately ONE function: month_charges() says
-- what a member owes for a month, and both callers use it --
--
--   the Bills screen, to show "October so far" live, before anything is owed
--   close_month(), to write those same lines as a draft invoice
--
-- so the review step cannot disagree with the invoice it is reviewing. If the
-- draft preview had its own query, the two would drift the first time a rate
-- changed mid-month, and the pilot would be told one number and billed another.
--
-- SPEC.md 4.6: "Closing a month locks that month's flights and generates the
-- invoice", "Review step: show the draft before anything is issued", "a sent
-- invoice never changes silently".

-- ---------------------------------------------------------------------------
-- The aeroplane's own calendar
--
-- A flight that lands at 6pm in Victoria is a UTC timestamp dated tomorrow, so
-- bucketing flights into months by the raw timestamp would push the last
-- evening of the month onto the next month's bill. aircraft_today() already
-- knew this; it only ever knew it about `now()`.
-- ---------------------------------------------------------------------------

create function public.aircraft_date(p_at timestamptz) returns date
language sql stable
as $$ select (p_at at time zone 'America/Vancouver')::date; $$;

comment on function public.aircraft_date(timestamptz) is
  'The calendar date a moment fell on where the aeroplane lives. Pair of fromInputValue/formatDate in lib/time.ts.';

-- Redefined in terms of the above so the zone is named once on this side of
-- the wire. Same answer as before.
create or replace function public.aircraft_today() returns date
language sql stable
as $$ select public.aircraft_date(now()); $$;

-- ---------------------------------------------------------------------------
-- GST
--
-- The rate lives on the company, not in code, because it is a tax rate and
-- tax rates change. Nothing is charged while gst_registered is false, which it
-- is until SPEC.md section 8 question 5 is answered -- but the arithmetic is
-- here now, because retrofitting tax onto issued invoices means re-stating
-- them.
-- ---------------------------------------------------------------------------

alter table public.company
  add column gst_rate numeric(6,4) not null default 0.0500
    check (gst_rate >= 0 and gst_rate < 1);

comment on column public.company.gst_rate is
  'GST fraction applied to taxable lines when gst_registered. 0.05 federal GST; a province with HST would raise this.';

-- ---------------------------------------------------------------------------
-- Who recorded a payment
--
-- The owner''s rule, 13 Oct 2026: a payment is recorded by an admin OTHER than
-- the member it credits, whenever there is another admin to ask. Both owners
-- will be admins, so "admin only" on its own would let either of them clear
-- their own balance unseen.
--
-- Same shape as expense approval (SPEC.md 4.7 "the other co-owner approves"),
-- and the same reason: the person who benefits is not the person who confirms.
-- ---------------------------------------------------------------------------

alter table public.ledger_entry
  add column recorded_by uuid references public.member(id) on delete set null;

comment on column public.ledger_entry.recorded_by is
  'The member who entered this row. Stamped from the session; a caller cannot choose it.';

create function public.ledger_entry_stamp_recorded_by()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- coalesce, not a bare assignment: a seed or a restore runs with no session
  -- and must be able to state who recorded a historical payment. There is no
  -- hole here, because an insert with no session is already refused by RLS.
  new.recorded_by := coalesce(public.current_member_id(), new.recorded_by);
  return new;
end;
$$;

create trigger ledger_entry_stamp_recorded_by
  before insert on public.ledger_entry
  for each row execute function public.ledger_entry_stamp_recorded_by();

create function public.guard_payment_four_eyes()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.kind not in ('payment', 'payout') then
    return new;
  end if;

  if new.recorded_by is null or new.recorded_by <> new.member_id then
    return new;
  end if;

  -- Recording your own. Allowed only when there is nobody else who could.
  if exists (
    select 1 from public.member m
    where m.is_active
      and m.role = 'admin'::public.member_role
      and m.id <> new.member_id
  ) then
    raise exception
      'a % to member % must be recorded by another admin', new.kind, new.member_id;
  end if;

  return new;
end;
$$;

-- Fires after the stamp trigger: alphabetically g < l would be wrong, so this
-- is named to sort after ledger_entry_stamp_recorded_by.
create trigger ledger_entry_zz_four_eyes
  before insert on public.ledger_entry
  for each row execute function public.guard_payment_four_eyes();

-- ---------------------------------------------------------------------------
-- What a month costs
-- ---------------------------------------------------------------------------

-- The flights one member is billed for in one month. Factored out because
-- issue_invoice() has to lock exactly the flights the charges were computed
-- from; two copies of this WHERE clause would eventually disagree, and the
-- symptom would be a flight billed twice or never.
create function public.month_flight_ids(
  p_aircraft_id uuid,
  p_member_id   uuid,
  p_month       date
)
returns setof uuid
language sql
stable
as $$
  select f.id
  from public.flight f
  where f.aircraft_id = p_aircraft_id
    and f.pilot_member_id = p_member_id
    -- 'draft' is still flying or still being corrected; 'billed' is already on
    -- an invoice. Only a confirmed flight is ready to be charged for.
    and f.status = 'confirmed'
    and f.billed_hours is not null
    and public.aircraft_date(f.start_at)
        between date_trunc('month', p_month)::date
            and (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
$$;

-- The member's share of a monthly fixed cost, as a fraction of 1.
--
-- All three arms of fixed_cost_split are implemented even though this company
-- uses ownership_pct, because a setting that silently bills the wrong split
-- when flipped is worse than no setting.
create function public.fixed_cost_share(
  p_aircraft_id uuid,
  p_member_id   uuid,
  p_month       date
)
returns numeric
language plpgsql
stable
set search_path = ''
as $$
declare
  v_split public.fixed_cost_split;
  v_start date := date_trunc('month', p_month)::date;
  v_share numeric;
begin
  select a.fixed_cost_split into v_split
  from public.aircraft a where a.id = p_aircraft_id;

  if v_split = 'ownership_pct' then
    select o.pct / 100 into v_share
    from public.ownership_as_of(p_aircraft_id, v_start) o
    where o.member_id = p_member_id;

  elsif v_split = 'equal' then
    -- Among the owners of record that month, not among everyone on the roster:
    -- an owner who has exited sits at 0% and does not pay hangarage.
    select case when count(*) = 0 then null else 1.0 / count(*) end
      into v_share
    from public.ownership_as_of(p_aircraft_id, v_start) o
    where o.pct > 0
      and exists (
        select 1 from public.ownership_as_of(p_aircraft_id, v_start) mine
        where mine.member_id = p_member_id and mine.pct > 0
      );

  elsif v_split = 'hours_flown' then
    select case when sum(f.billed_hours) = 0 then null
                else sum(f.billed_hours) filter (where f.pilot_member_id = p_member_id)
                     / sum(f.billed_hours) end
      into v_share
    from public.flight f
    where f.aircraft_id = p_aircraft_id
      and f.status = 'confirmed'
      and f.billed_hours is not null
      and public.aircraft_date(f.start_at)
          between v_start and (v_start + interval '1 month - 1 day')::date;
  end if;

  return coalesce(v_share, 0);
end;
$$;

/*
 * Everything one member owes for one month, as proposed invoice lines.
 *
 * Flight time comes back as one line PER RATE COMPONENT, because the general
 * ledger needs fuel, reserve and operating revenue in different accounts and
 * the reserve dashboard (SPEC.md 4.8) needs the accrual per component. SPEC.md
 * 4.8 also says "pilots see one rate", so the Bills screen sums them back into
 * a single row -- period_hours is repeated on each of those lines so it can do
 * that without a second query inventing its own idea of the hours.
 *
 * The rate is resolved per flight date, not per month, so a rate that changes
 * on the 15th bills the first half at the old price.
 *
 * Expense credits (SPEC.md 4.6) are missing because the expense table is a
 * later phase. When it lands it becomes another UNION arm here, and the Bills
 * screen gets its "Receipt credits" row for free.
 */
create function public.month_charges(
  p_aircraft_id uuid,
  p_member_id   uuid,
  p_month       date
)
returns table (
  kind            public.ledger_entry_kind,
  description     text,
  quantity        numeric,
  unit_rate       numeric,
  amount          numeric,
  gst_amount      numeric,
  tax_treatment   public.tax_treatment,
  gl_account_code text,
  sort_order      int,
  period_hours    numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_start    date := date_trunc('month', p_month)::date;
  v_gst      numeric;
  v_hours    numeric;
  v_share    numeric;
begin
  -- SPEC.md 4.6: "Only an admin sees all pilots' numbers." This function is
  -- security definer, so without this check any member could price any other
  -- member's month.
  if p_member_id is distinct from public.current_member_id()
     and not public.is_admin() then
    raise exception 'not allowed to read another member''s charges';
  end if;

  select case when c.gst_registered then c.gst_rate else 0 end
    into v_gst
  from public.company c
  join public.aircraft a on a.company_id = c.id
  where a.id = p_aircraft_id;

  select coalesce(sum(f.billed_hours), 0) into v_hours
  from public.flight f
  where f.id in (
    select public.month_flight_ids(p_aircraft_id, p_member_id, p_month)
  );

  v_share := public.fixed_cost_share(p_aircraft_id, p_member_id, p_month);

  return query
  select
    'flight_charge'::public.ledger_entry_kind,
    format('Flight time — %s', x.name),
    x.hours,
    x.rate_per_hour,
    x.amount,
    case when x.tax_treatment = 'taxable'
         then round(x.amount * v_gst, 2) else 0 end,
    x.tax_treatment,
    x.gl_account_code,
    100 + x.sort_order,
    v_hours
  from (
    select
      c.name,
      c.rate_per_hour,
      c.gl_account_code,
      c.tax_treatment,
      c.sort_order,
      sum(f.billed_hours)                          as hours,
      round(sum(f.billed_hours) * c.rate_per_hour, 2) as amount
    from public.flight f
    -- Joined through the resolver rather than to a single schedule, so each
    -- flight is priced at the rate that was in force the day it was flown.
    join public.rate_component c
      on c.schedule_id = public.rate_schedule_as_of(
           f.aircraft_id, public.aircraft_date(f.start_at))
    where f.id in (
      select public.month_flight_ids(p_aircraft_id, p_member_id, p_month)
    )
    group by c.name, c.rate_per_hour, c.gl_account_code, c.tax_treatment, c.sort_order
  ) x

  union all

  select
    fc.kind,
    format('%s · %s share', fc.name,
           trim(to_char(v_share * 100, 'FM999990.##')) || '%'),
    v_share,
    fc.monthly_amount,
    round(fc.monthly_amount * v_share, 2),
    case when fc.tax_treatment = 'taxable'
         then round(fc.monthly_amount * v_share * v_gst, 2) else 0 end,
    fc.tax_treatment,
    fc.gl_account_code,
    200,
    null::numeric
  -- Costs as they stood on the first of the month: a hangarage rise on the
  -- 20th applies to the next month's bill, not retroactively to this one.
  from public.fixed_costs_as_of(p_aircraft_id, v_start) fc
  where v_share > 0 and round(fc.monthly_amount * v_share, 2) > 0

  order by 9, 2;
end;
$$;

-- ---------------------------------------------------------------------------
-- Closing the month
-- ---------------------------------------------------------------------------

/*
 * Build (or rebuild) the draft invoices for a month.
 *
 * Re-runnable on purpose: an admin who closes the month, spots a flight with
 * the wrong times, fixes it and closes again should get the corrected draft.
 * That is safe only while the invoice is a draft, which is exactly what the
 * immutability triggers already enforce -- so this deletes and rewrites the
 * lines rather than trying to reconcile them.
 *
 * Returns the number of drafts standing afterwards.
 */
create function public.close_month(p_aircraft_id uuid, p_month date)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company  uuid;
  v_start    date := date_trunc('month', p_month)::date;
  v_member   record;
  v_invoice  uuid;
  v_status   public.invoice_status;
  v_lines    int;
  v_built    int := 0;
begin
  if not public.is_admin() then
    raise exception 'only an admin can close a month';
  end if;

  select a.company_id into v_company
  from public.aircraft a where a.id = p_aircraft_id;
  if v_company is null then
    raise exception 'no such aircraft: %', p_aircraft_id;
  end if;

  if v_start > public.aircraft_today() then
    raise exception 'cannot close %, it has not started yet', to_char(v_start, 'Mon YYYY');
  end if;

  for v_member in
    select m.id from public.member m where m.is_active order by m.full_name
  loop
    select i.id, i.status into v_invoice, v_status
    from public.invoice i
    where i.company_id = v_company
      and i.member_id = v_member.id
      and i.period_month = v_start;

    -- Reset explicitly. A plpgsql variable that a SELECT INTO found no row for
    -- keeps the value it had on the previous turn of this loop, so without
    -- this the second member would inherit the first member's invoice.
    if not found then
      v_invoice := null;
      v_status  := null;
    end if;

    -- An issued invoice is the record of what was sent. Rebuilding it would be
    -- the "sent invoice changes silently" that SPEC.md 4.6 forbids; the fix for
    -- a mistake found afterwards is an adjustment on the next bill.
    if v_status is not null and v_status <> 'draft' then
      continue;
    end if;

    if v_invoice is null then
      insert into public.invoice (company_id, member_id, period_month)
      values (v_company, v_member.id, v_start)
      returning id into v_invoice;
    else
      delete from public.ledger_entry where invoice_id = v_invoice;
    end if;

    insert into public.ledger_entry (
      company_id, member_id, invoice_id, kind, entry_date, description,
      quantity, unit_rate, amount, gst_amount, tax_treatment, gl_account_code
    )
    select
      v_company, v_member.id, v_invoice, c.kind,
      -- Dated the last day of the period, not today: the charge belongs to the
      -- month it was incurred in, whenever the admin got round to closing it.
      (v_start + interval '1 month - 1 day')::date,
      c.description, c.quantity, c.unit_rate, c.amount, c.gst_amount,
      c.tax_treatment, c.gl_account_code
    from public.month_charges(p_aircraft_id, v_member.id, v_start) c;

    get diagnostics v_lines = row_count;

    -- A member who did not fly and owns nothing gets no invoice at all, rather
    -- than a $0.00 one to ignore.
    if v_lines = 0 then
      delete from public.invoice where id = v_invoice;
    else
      v_built := v_built + 1;
    end if;
  end loop;

  return v_built;
end;
$$;

/*
 * Issue a draft: allocate its number, and lock the flights behind it.
 *
 * Numbering happens here rather than at draft time because a draft may be
 * discarded, and a discarded number is a gap a GST invoice run must not have.
 */
create function public.issue_invoice(p_invoice_id uuid)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv      public.invoice;
  v_aircraft uuid;
  v_number   bigint;
begin
  if not public.is_admin() then
    raise exception 'only an admin can issue an invoice';
  end if;

  select * into v_inv from public.invoice where id = p_invoice_id;
  if not found then
    raise exception 'no such invoice: %', p_invoice_id;
  end if;
  if v_inv.status <> 'draft' then
    raise exception 'invoice % is already %', p_invoice_id, v_inv.status;
  end if;

  perform 1 from public.ledger_entry where invoice_id = p_invoice_id;
  if not found then
    raise exception 'invoice % has no lines', p_invoice_id;
  end if;

  -- Without these the journal export emits lines no accounting system can
  -- accept, and it would be found out a year later at the first reconciliation.
  perform 1 from public.company c
   where c.id = v_inv.company_id
     and c.ar_account_code is not null
     and c.bank_account_code is not null;
  if not found then
    raise exception
      'set the receivables and bank account codes before issuing invoices';
  end if;

  v_number := public.next_invoice_number(v_inv.company_id);

  update public.invoice
     set number = v_number, status = 'issued', issued_at = now()
   where id = p_invoice_id;

  select a.id into v_aircraft
  from public.aircraft a where a.company_id = v_inv.company_id
  order by a.created_at limit 1;

  -- The lock. Exactly the flights month_charges priced, because both ask the
  -- same function which ones those are.
  update public.flight
     set status = 'billed', invoice_id = p_invoice_id
   where id in (
     select public.month_flight_ids(v_aircraft, v_inv.member_id, v_inv.period_month)
   );

  return v_number;
end;
$$;

/*
 * Record money arriving.
 *
 * p_amount is given as a positive figure -- "$412.50 landed" -- and stored
 * negative, because in this ledger positive means the member owes more. The
 * check constraint would catch the mistake, but the caller should not have to
 * think about the sign convention to type in a cheque.
 */
create function public.record_payment(
  p_member_id uuid,
  p_amount    numeric,
  p_paid_on   date,
  p_note      text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company uuid;
  v_bank    text;
  v_id      uuid;
begin
  if not public.is_admin() then
    raise exception 'only an admin can record a payment';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'a payment must be a positive amount';
  end if;

  select c.id, c.bank_account_code into v_company, v_bank
  from public.company c order by c.created_at limit 1;

  if v_bank is null then
    raise exception 'set the bank account code before recording payments';
  end if;

  insert into public.ledger_entry (
    company_id, member_id, kind, entry_date, description,
    amount, tax_treatment, gl_account_code
  ) values (
    v_company, p_member_id, 'payment', coalesce(p_paid_on, public.aircraft_today()),
    coalesce(nullif(btrim(p_note), ''), 'Payment received'),
    -p_amount, 'out_of_scope', v_bank
  )
  returning id into v_id;

  -- Settling is a convenience, not an accounting fact: the balance is the sum
  -- of the ledger either way. So it is all-or-nothing against the whole
  -- balance rather than an allocation of this payment to particular invoices,
  -- which would need a matching table and would still be guesswork.
  if public.member_balance(p_member_id) <= 0 then
    update public.invoice
       set status = 'settled', settled_at = now()
     where member_id = p_member_id and status = 'issued';
  end if;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants
--
-- The security definer functions do their own authorisation above, so EXECUTE
-- is granted to authenticated and the function decides. anon gets nothing.
-- ---------------------------------------------------------------------------

revoke all on function public.month_charges(uuid, uuid, date)   from anon;
revoke all on function public.close_month(uuid, date)            from anon;
revoke all on function public.issue_invoice(uuid)                from anon;
revoke all on function public.record_payment(uuid, numeric, date, text) from anon;
revoke all on function public.fixed_cost_share(uuid, uuid, date) from anon;
revoke all on function public.month_flight_ids(uuid, uuid, date) from anon;
