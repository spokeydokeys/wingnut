-- Receipts: what was bought, who paid, and who else agreed to it.
--
-- SPEC.md 4.7. Two kinds of purchase arrive through the same screen and they
-- are not the same transaction at all:
--
--   payer = 'member'   an owner paid out of their own pocket. The company owes
--                      them the WHOLE amount back (confirmed 13 Oct 2026: fuel
--                      a pilot buys is a full reimbursement from the shared
--                      pool, not a share of it), so an approved one becomes a
--                      credit on their next bill.
--
--   payer = 'company'  the company debit card was used. The money has already
--                      left the company account; nobody is owed anything, so
--                      there is no credit and nothing to approve. It is
--                      recorded because the other owner is entitled to see
--                      what the card was used for, and because the GL needs
--                      the coding and the receipt image.
--
-- That split is why status is tied to payer by a check constraint rather than
-- left as a convention: 'recorded' is the only status a company-card purchase
-- can hold, and an approval path it never walks cannot be walked by accident.
--
-- THE CREDIT IS NOT POSTED AT APPROVAL. It is derived by month_charges and
-- written by close_month, exactly like a flight charge, and locked to the
-- invoice by issue_invoice. An expense table that also posted its own ledger
-- row would be a second source for the same money, and the first re-close
-- would double it. month_charges said as much in 20261013101500: "it becomes
-- another UNION arm here". It now is.
--
-- Editability, decided with the owner 13 Oct 2026:
--   - an APPROVED expense is frozen. SPEC.md 4.7: corrections are adjustments.
--   - a RECORDED (company-card) one stays editable until the month it falls in
--     is closed. Nothing is owed on it, so the immutability rule that exists to
--     protect a posted credit does not apply -- and a mistyped total on a card
--     purchase is a coding error, best fixed in place while that is still free.
--
-- Deliberately NOT here:
--   - OCR prefill (SPEC.md 4.7 step 2). Deferred: it is an accelerator on top
--     of a form that has to exist, work offline and be confirmed field by field
--     regardless, and adding it later changes no schema.
--   - Anything that claims an input tax credit. company.gst_registered is still
--     false. The tax fields are here now because retrofitting tax onto issued
--     invoices means re-stating them.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

create type public.expense_payer as enum ('company', 'member');

create type public.expense_status as enum
  ('recorded', 'submitted', 'approved', 'rejected');

-- Which pot bears the cost. Nothing reads this yet; the reserve dashboard
-- (SPEC.md 4.8) will, and a maintenance bill paid out of the overhaul reserve
-- is not the same event as one paid out of the operating float. Recording it
-- from the start costs a column; deciding it afterwards means guessing at
-- history.
create type public.expense_charge_to as enum ('pool', 'reserve');

-- ---------------------------------------------------------------------------
-- Has a month been closed?
--
-- "Closed" means an invoice for that period has left draft. A draft is a
-- proposal that close_month rewrites freely, so a month with only drafts is
-- still open.
--
-- security definer because invoice is scoped per member by RLS: a pilot asking
-- whether September is closed would otherwise be answered from their own
-- invoice alone.
-- ---------------------------------------------------------------------------

create function public.month_is_closed(p_company_id uuid, p_month date)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.invoice i
    where i.company_id = p_company_id
      and i.period_month = date_trunc('month', p_month)::date
      and i.status <> 'draft'::public.invoice_status
  );
$$;

-- ---------------------------------------------------------------------------
-- expense
-- ---------------------------------------------------------------------------

create table public.expense (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.company(id) on delete restrict,
  aircraft_id uuid not null references public.aircraft(id) on delete restrict,

  payer       public.expense_payer not null,
  -- Who is owed the money. Null for a company-card purchase, because nobody
  -- is: the company has already paid itself out.
  paid_by_member_id uuid references public.member(id) on delete restrict,

  vendor      text not null check (length(trim(vendor)) > 0),
  spent_on    date not null,

  -- As printed on the receipt: tax included. The split below is for the GL,
  -- but the figure a pilot can check against the paper is the total.
  total_amount numeric(12,2) not null check (total_amount > 0),
  gst_amount   numeric(12,2) not null default 0 check (gst_amount >= 0),
  tax_treatment public.tax_treatment not null default 'taxable',
  -- The supplier's registration number, which an input tax credit claim needs
  -- and which only exists on the paper. Captured even while the company is not
  -- registered, because the receipt will be long gone by the time it is.
  vendor_gst_number text,

  -- The coding. Which expense account in the company's own chart -- so the
  -- categories a pilot picks from ARE the chart, and there is no second list to
  -- keep in step with it.
  gl_account_code text not null,
  charge_to       public.expense_charge_to not null default 'pool',

  -- Fuel only, and the reason the Pool page can show cents per litre.
  litres      numeric(8,2) check (litres > 0),

  note        text,

  -- Optional links. set null on delete both ways: a cancelled flight or a
  -- cleared snag must not take the receipt with it.
  flight_id   uuid references public.flight(id) on delete set null,
  snag_id     uuid references public.snag(id) on delete set null,

  -- The object key in the receipts bucket, never a URL. Storage is behind an
  -- interface (portability rule, 12 Oct 2026) and a Supabase URL in a column
  -- is a migration that has to be done with string surgery later.
  --
  -- Nullable on purpose: the dock has no signal. A receipt whose image failed
  -- to upload must still be enterable, and is shown as missing its photo
  -- rather than refused. Approval is where the image becomes compulsory.
  receipt_key text,

  status      public.expense_status not null,

  submitted_by uuid not null references public.member(id) on delete restrict,

  -- Who decided. One pair of columns for both outcomes, because the status
  -- already says which it was.
  reviewed_by uuid references public.member(id) on delete restrict,
  reviewed_at timestamptz,
  review_note text,

  -- Set by issue_invoice, which is what stops one receipt being credited
  -- twice. Same role as flight.invoice_id.
  invoice_id  uuid references public.invoice(id) on delete restrict,

  external_ref text,
  synced_at    timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  -- The account must exist in the company's own chart, for the same reason
  -- ledger_entry carries this foreign key: a journal line naming an account
  -- the accounting system has never heard of is rejected at import.
  foreign key (company_id, gl_account_code)
    references public.gl_account (company_id, code) on delete restrict,

  constraint expense_member_paid_has_payer
    check ((payer = 'member') = (paid_by_member_id is not null)),

  -- The heart of it: a company-card purchase has no approval path at all.
  constraint expense_status_matches_payer check (
    case payer
      when 'company' then status = 'recorded'
      when 'member'  then status in ('submitted', 'approved', 'rejected')
    end
  ),

  constraint expense_reviewed_has_timestamp
    check ((status in ('approved', 'rejected')) = (reviewed_at is not null)),

  -- Only an approved reimbursement is ever a line of a bill.
  constraint expense_invoiced_only_when_approved
    check (invoice_id is null or status = 'approved'),

  -- Same two rules as ledger_entry, for the same reasons: tax cannot be
  -- claimed on a line that carries none, and it is part of the total rather
  -- than on top of it.
  constraint expense_gst_only_when_taxable
    check (gst_amount = 0 or tax_treatment = 'taxable'),
  constraint expense_gst_within_total
    check (gst_amount <= total_amount)
);

-- The approvals queue.
create index expense_awaiting_idx on public.expense (spent_on desc)
  where status = 'submitted';

create index expense_payer_idx
  on public.expense (paid_by_member_id, spent_on desc);

-- SPEC.md 4.7: "flag a likely duplicate on the same vendor, date and amount".
-- An index rather than a unique constraint, because the same vendor on the same
-- day for the same amount is sometimes two real fills.
create index expense_duplicate_idx
  on public.expense (company_id, lower(btrim(vendor)), spent_on, total_amount);

create trigger expense_set_updated_at
  before update on public.expense
  for each row execute function public.set_updated_at();

-- What "the same receipt twice" means, in one place rather than in whichever
-- screen happens to ask. Matches expense_duplicate_idx exactly.
create function public.expense_duplicates(p_expense_id uuid)
returns setof uuid
language sql
stable
as $$
  select other.id
  from public.expense e
  join public.expense other
    on other.id <> e.id
   and other.company_id = e.company_id
   and lower(btrim(other.vendor)) = lower(btrim(e.vendor))
   and other.spent_on = e.spent_on
   and other.total_amount = e.total_amount
  where e.id = p_expense_id
  order by other.created_at;
$$;

-- ---------------------------------------------------------------------------
-- Who entered it, who decided it
--
-- Same shape as task_stamp_completed and snag_stamp_cleared: stamped by the
-- database on the TRANSITION only, so a crafted request cannot claim the other
-- owner approved it, and re-saving an approved row keeps the original stamp.
-- ---------------------------------------------------------------------------

create function public.expense_stamp_people()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    -- coalesce, not a bare assignment: a seed or a restore runs with no
    -- session and must still be able to say who entered a historical receipt.
    -- No hole, because an insert with no session is refused by RLS anyway.
    new.submitted_by := coalesce(public.current_member_id(), new.submitted_by);
  else
    new.submitted_by := old.submitted_by;
  end if;

  if new.status in ('approved', 'rejected') then
    if tg_op = 'INSERT' or old.status not in ('approved', 'rejected') then
      new.reviewed_at := now();
      new.reviewed_by := coalesce(public.current_member_id(), new.reviewed_by);
    else
      new.reviewed_at := old.reviewed_at;
      new.reviewed_by := old.reviewed_by;
    end if;
  else
    new.reviewed_at := null;
    new.reviewed_by := null;
  end if;

  return new;
end;
$$;

create trigger expense_stamp_people
  before insert or update on public.expense
  for each row execute function public.expense_stamp_people();

-- ---------------------------------------------------------------------------
-- Freezing
--
-- Named to sort after expense_stamp_people, which must run first: this reads
-- the stamped columns.
-- ---------------------------------------------------------------------------

create function public.expense_zz_guard_frozen()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status = 'approved' then
    if tg_op = 'DELETE' then
      raise exception
        'expense % is approved and cannot be deleted; raise an adjustment instead',
        old.id;
    end if;

    -- Only the invoice link and the sync fields move after approval, and both
    -- are written by machinery rather than by a person.
    if (new.company_id, new.aircraft_id, new.payer, new.paid_by_member_id,
        new.vendor, new.spent_on, new.total_amount, new.gst_amount,
        new.tax_treatment, new.vendor_gst_number, new.gl_account_code,
        new.charge_to, new.litres, new.note, new.flight_id, new.snag_id,
        new.receipt_key, new.status, new.submitted_by, new.reviewed_by,
        new.reviewed_at)
       is distinct from
       (old.company_id, old.aircraft_id, old.payer, old.paid_by_member_id,
        old.vendor, old.spent_on, old.total_amount, old.gst_amount,
        old.tax_treatment, old.vendor_gst_number, old.gl_account_code,
        old.charge_to, old.litres, old.note, old.flight_id, old.snag_id,
        old.receipt_key, old.status, old.submitted_by, old.reviewed_by,
        old.reviewed_at)
    then
      raise exception
        'expense % is approved and cannot be changed; raise an adjustment instead',
        old.id;
    end if;

    return new;
  end if;

  -- A company-card purchase owes nobody anything, so it stays editable --
  -- until the month it falls in has been closed, at which point its coding is
  -- part of a statement that has gone out.
  if old.status = 'recorded'
     and public.month_is_closed(old.company_id, old.spent_on) then
    raise exception
      'expense % falls in a closed month and can no longer be changed', old.id;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger expense_zz_guard_frozen
  before update or delete on public.expense
  for each row execute function public.expense_zz_guard_frozen();

-- ---------------------------------------------------------------------------
-- Approving
--
-- SPEC.md 4.7: "the other co-owner approves". aircraft.expense_approval_rule
-- decides who counts as the other co-owner, and the rule is applied here
-- rather than in the Server Action because a Server Action is a public POST
-- endpoint.
--
-- Same escape hatch as guard_payment_four_eyes: approving your own is allowed
-- only when there is nobody else who could. A sole remaining owner with an
-- unapprovable pile of receipts is worse than a self-approval that the
-- reviewed_by stamp records honestly.
-- ---------------------------------------------------------------------------

create function public.expense_zz_validate()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_company uuid;
begin
  -- The aircraft and the chart of accounts have to belong to the same company,
  -- or a receipt could be coded against another company's account.
  select a.company_id into v_company
  from public.aircraft a where a.id = new.aircraft_id;

  if v_company is distinct from new.company_id then
    raise exception 'aircraft % does not belong to company %',
      new.aircraft_id, new.company_id;
  end if;

  -- Revenue is not a category of spending. Miscoding a fuel purchase as
  -- revenue balances in this schema and is found out a year later, at the
  -- first reconciliation.
  perform 1 from public.gl_account g
   where g.company_id = new.company_id
     and g.code = new.gl_account_code
     and g.type = 'expense'::public.gl_account_type;
  if not found then
    raise exception '% is not an expense account', new.gl_account_code;
  end if;

  if new.status <> 'approved' then
    return new;
  end if;

  -- CRA keeps receipts for six years, and an approved reimbursement with no
  -- image is a payment with no support.
  if new.receipt_key is null then
    raise exception 'expense % cannot be approved without its receipt', new.id;
  end if;

  if new.reviewed_by is not null
     and new.reviewed_by = new.paid_by_member_id
     and exists (
       select 1
       from public.member m
       join public.aircraft a on a.id = new.aircraft_id
       where m.is_active
         and m.id <> new.paid_by_member_id
         and (a.expense_approval_rule
                = 'any_other_owner'::public.expense_approval_rule
              or m.role = 'admin'::public.member_role)
     )
  then
    raise exception
      'expense % must be approved by somebody other than the member it pays',
      new.id;
  end if;

  return new;
end;
$$;

create trigger expense_zz_validate
  before insert or update on public.expense
  for each row execute function public.expense_zz_validate();

-- ---------------------------------------------------------------------------
-- The credit on the bill
-- ---------------------------------------------------------------------------

/*
 * The receipts one member is credited for in one month.
 *
 * Factored out for the same reason month_flight_ids was: issue_invoice has to
 * lock exactly the receipts the credit was computed from, and two copies of
 * this WHERE clause would eventually disagree -- the symptom being a receipt
 * reimbursed twice, or never.
 *
 * Note the date test: approved ON OR BEFORE the end of the period, not
 * approved WITHIN it. Approval needs the other owner, so it routinely lands
 * after the month the fuel was bought in. Anything approved and not yet
 * credited is swept into the next month that gets closed, which is what stops
 * a late approval being stranded between two issued invoices forever.
 */
create function public.month_expense_ids(
  p_aircraft_id uuid,
  p_member_id   uuid,
  p_month       date
)
returns setof uuid
language sql
stable
as $$
  select e.id
  from public.expense e
  where e.aircraft_id = p_aircraft_id
    and e.payer = 'member'::public.expense_payer
    and e.paid_by_member_id = p_member_id
    and e.status = 'approved'::public.expense_status
    and e.invoice_id is null
    and public.aircraft_date(e.reviewed_at)
        <= (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
$$;

/*
 * Replaced to add the third UNION arm promised in 20261013101500: the receipt
 * credits. Everything else is as it was.
 *
 * The credit is the WHOLE receipt -- amount and gst_amount both negative, so
 * they sum to exactly what the pilot paid at the pump. Splitting the tax out
 * is for the journal, not for the reimbursement.
 */
create or replace function public.month_charges(
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

  union all

  select
    'expense_credit'::public.ledger_entry_kind,
    format('Receipt — %s, %s', e.vendor, to_char(e.spent_on, 'FMDD Mon')),
    e.litres,
    case when e.litres is null then null
         else round(e.total_amount / e.litres, 4) end,
    -(e.total_amount - e.gst_amount),
    -e.gst_amount,
    e.tax_treatment,
    e.gl_account_code,
    300,
    null::numeric
  from public.expense e
  where e.id in (
    select public.month_expense_ids(p_aircraft_id, p_member_id, v_start)
  )

  order by 9, 2;
end;
$$;

/*
 * Replaced to lock the receipts behind the invoice as well as the flights.
 * Everything else is as it was in 20261013101500.
 *
 * Both locks use the same ids-function the charges were computed from, so what
 * is locked is exactly what was billed.
 */
create or replace function public.issue_invoice(p_invoice_id uuid)
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

  update public.flight
     set status = 'billed', invoice_id = p_invoice_id
   where id in (
     select public.month_flight_ids(v_aircraft, v_inv.member_id, v_inv.period_month)
   );

  update public.expense
     set invoice_id = p_invoice_id
   where id in (
     select public.month_expense_ids(v_aircraft, v_inv.member_id, v_inv.period_month)
   );

  return v_number;
end;
$$;

-- ---------------------------------------------------------------------------
-- Row level security
--
-- Every member reads every receipt. That is not laxness: the approval rule is
-- "the other co-owner", which cannot work if you cannot see what you are
-- approving, and the owner's instruction on 13 Oct 2026 was that a company
-- card purchase must be visible to the other owner.
--
-- Writes are open to any member as well, because the rules that actually
-- matter -- who may approve, what may change after approval -- are not
-- expressible as a policy. A policy refuses an UPDATE by matching no rows,
-- which reads on screen as "saved" and nothing changing; the triggers above
-- raise, which reads as an error. So the triggers hold the line and the
-- policies only keep strangers out.
-- ---------------------------------------------------------------------------

alter table public.expense enable row level security;

revoke all on public.expense from anon;

create policy expense_select_members on public.expense
  for select to authenticated using (public.current_member_id() is not null);

-- Entered by you, or by an admin on someone's behalf. submitted_by is stamped
-- from the session, so this is a belt on top of a brace.
create policy expense_insert_members on public.expense
  for insert to authenticated
  with check (submitted_by = public.current_member_id() or public.is_admin());

create policy expense_update_members on public.expense
  for update to authenticated
  using (public.current_member_id() is not null)
  with check (public.current_member_id() is not null);

-- Deleting is for a receipt entered by mistake, so it stays with whoever
-- entered it. An approved one cannot be deleted at all; the guard says so.
create policy expense_delete_own on public.expense
  for delete to authenticated using (submitted_by = public.current_member_id());

create policy expense_admin_all on public.expense
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

revoke all on function public.month_expense_ids(uuid, uuid, date) from anon;
revoke all on function public.month_is_closed(uuid, date)         from anon;
revoke all on function public.expense_duplicates(uuid)            from anon;

comment on table public.expense is
  'One receipt. payer decides everything else: a member-paid one is approved and credited, a company-card one is only recorded.';
comment on column public.expense.receipt_key is
  'Object key in the receipts bucket. Never a URL -- storage is swappable.';
comment on column public.expense.invoice_id is
  'Set by issue_invoice. Its presence is what stops a second reimbursement.';
comment on function public.month_expense_ids(uuid, uuid, date) is
  'Approved, uncredited receipts for one member, swept up to the end of a month.';
