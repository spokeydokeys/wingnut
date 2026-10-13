-- The money layer: rates, fixed costs, invoices and the ledger.
--
-- Two ideas carry the whole design.
--
-- 1. The ledger is the only place a balance comes from. ledger_entry rows ARE
--    the lines of an invoice (invoice_id points at their envelope), so there is
--    no second list of amounts to reconcile against. SPEC.md 4.6: "Never
--    compute balances anywhere else."
--
-- 2. Prices are effective-dated as whole schedules, the same snapshot pattern
--    as ownership_period. Raising the wet rate inserts a NEW schedule; it never
--    edits the old one, so a closed month keeps billing at the rate that was in
--    force when it was flown. SPEC.md 4.6: "A rate change applies from a date
--    forward and never rewrites past bills."
--
-- Accounting integration is export-first (decided 12 Oct 2026): this schema is
-- the operations and AR sub-ledger, and an accounting system is the general
-- ledger. The four things that makes possible later are built in from the
-- start, because retrofitting them means re-stating history:
--   - gl_account, a chart of accounts every charge maps to
--   - tax_treatment per line, not just a GST total
--   - external_ref + synced_at for idempotent one-way push
--   - gapless invoice numbers, which GST invoices legally require

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

create type public.gl_account_type as enum
  ('asset', 'liability', 'equity', 'revenue', 'expense');

-- Not just a GST rate. An accounting system needs to know WHY a line carries
-- no tax, because zero-rated and exempt supplies are reported differently and
-- affect input tax credit recovery.
create type public.tax_treatment as enum
  ('taxable', 'zero_rated', 'exempt', 'out_of_scope');

create type public.rate_component_kind as enum ('fuel', 'reserve', 'operating');

create type public.invoice_status as enum ('draft', 'issued', 'settled', 'void');

create type public.ledger_entry_kind as enum (
  'flight_charge', 'hangarage', 'insurance',
  'expense_credit', 'payment', 'payout', 'adjustment'
);

-- ---------------------------------------------------------------------------
-- Chart of accounts
--
-- Codes are the company's own, because they have to match whatever the
-- accountant sets up in QBO or Xero. Nothing here assumes a particular chart.
-- ---------------------------------------------------------------------------

create table public.gl_account (
  company_id uuid not null references public.company(id) on delete cascade,
  code       text not null,
  name       text not null,
  type       public.gl_account_type not null,
  created_at timestamptz not null default now(),
  primary key (company_id, code),
  constraint gl_account_code_not_blank check (btrim(code) <> '')
);

-- The two accounts the double-entry journal needs but a charge line cannot
-- carry: every invoice debits receivables, every payment credits them and
-- debits the bank.
alter table public.company
  add column ar_account_code   text,
  add column bank_account_code text;

comment on column public.company.ar_account_code is
  'Accounts receivable code in the external GL. Required before issuing.';
comment on column public.company.bank_account_code is
  'Operating bank account code in the external GL. Required before issuing.';

-- ---------------------------------------------------------------------------
-- Rate schedules
--
-- Pilots see one wet rate; it is stored as the named components that sum to
-- it (SPEC.md 4.8) so the Pool page can show fuel cost per hour against the
-- fuel component, and reserve accrual against the reserve components.
-- ---------------------------------------------------------------------------

create table public.rate_schedule (
  id             uuid primary key default gen_random_uuid(),
  aircraft_id    uuid not null references public.aircraft(id) on delete cascade,
  effective_from date not null,
  note           text,
  created_at     timestamptz not null default now(),
  unique (aircraft_id, effective_from)
);

create table public.rate_component (
  id              uuid primary key default gen_random_uuid(),
  schedule_id     uuid not null references public.rate_schedule(id) on delete cascade,
  name            text not null,
  kind            public.rate_component_kind not null,
  rate_per_hour   numeric(10,4) not null,
  gl_account_code text not null,
  tax_treatment   public.tax_treatment not null default 'taxable',
  sort_order      int not null default 0,
  unique (schedule_id, name),
  constraint rate_component_non_negative check (rate_per_hour >= 0)
);

create index rate_component_schedule_idx on public.rate_component (schedule_id);

create function public.rate_schedule_as_of(p_aircraft_id uuid, p_on date)
returns uuid
language sql
stable
as $$
  select s.id
  from public.rate_schedule s
  where s.aircraft_id = p_aircraft_id
    and s.effective_from <= p_on
  order by s.effective_from desc
  limit 1;
$$;

create function public.rate_components_as_of(p_aircraft_id uuid, p_on date)
returns table (
  name            text,
  kind            public.rate_component_kind,
  rate_per_hour   numeric,
  gl_account_code text,
  tax_treatment   public.tax_treatment
)
language sql
stable
as $$
  select c.name, c.kind, c.rate_per_hour, c.gl_account_code, c.tax_treatment
  from public.rate_component c
  where c.schedule_id = public.rate_schedule_as_of(p_aircraft_id, p_on)
  order by c.sort_order, c.name;
$$;

-- The single figure a pilot is quoted.
create function public.wet_rate_as_of(p_aircraft_id uuid, p_on date)
returns numeric
language sql
stable
as $$
  select coalesce(sum(rate_per_hour), 0)
  from public.rate_components_as_of(p_aircraft_id, p_on);
$$;

-- ---------------------------------------------------------------------------
-- Fixed costs
--
-- Hangarage and insurance: billed monthly and split between owners by the
-- aircraft's fixed_cost_split setting, which for this company is ownership
-- percent resolved through ownership_as_of.
-- ---------------------------------------------------------------------------

create table public.fixed_cost_schedule (
  id             uuid primary key default gen_random_uuid(),
  aircraft_id    uuid not null references public.aircraft(id) on delete cascade,
  effective_from date not null,
  note           text,
  created_at     timestamptz not null default now(),
  unique (aircraft_id, effective_from)
);

create table public.fixed_cost (
  id              uuid primary key default gen_random_uuid(),
  schedule_id     uuid not null references public.fixed_cost_schedule(id) on delete cascade,
  name            text not null,
  kind            public.ledger_entry_kind not null,
  monthly_amount  numeric(12,2) not null,
  gl_account_code text not null,
  tax_treatment   public.tax_treatment not null default 'taxable',
  sort_order      int not null default 0,
  unique (schedule_id, name),
  constraint fixed_cost_non_negative check (monthly_amount >= 0),
  -- Only the two recurring charge kinds make sense as a monthly fixed cost.
  constraint fixed_cost_kind_is_recurring
    check (kind in ('hangarage', 'insurance'))
);

create index fixed_cost_schedule_idx on public.fixed_cost (schedule_id);

create function public.fixed_costs_as_of(p_aircraft_id uuid, p_on date)
returns table (
  name            text,
  kind            public.ledger_entry_kind,
  monthly_amount  numeric,
  gl_account_code text,
  tax_treatment   public.tax_treatment
)
language sql
stable
as $$
  select f.name, f.kind, f.monthly_amount, f.gl_account_code, f.tax_treatment
  from public.fixed_cost f
  where f.schedule_id = (
    select s.id
    from public.fixed_cost_schedule s
    where s.aircraft_id = p_aircraft_id
      and s.effective_from <= p_on
    order by s.effective_from desc
    limit 1
  )
  order by f.sort_order, f.name;
$$;

-- ---------------------------------------------------------------------------
-- Invoices
--
-- One per member per calendar month. period_month stores the first of the
-- month; the constraint keeps anything else out.
-- ---------------------------------------------------------------------------

create table public.invoice (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references public.company(id) on delete restrict,
  member_id     uuid not null references public.member(id) on delete restrict,
  period_month  date not null,
  number        bigint,
  status        public.invoice_status not null default 'draft',
  issued_at     timestamptz,
  settled_at    timestamptz,
  note          text,
  -- Set by the accounting-system push, never by hand. synced_at without an
  -- external_ref means the push started and did not finish.
  external_ref  text,
  synced_at     timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (company_id, member_id, period_month),
  unique (company_id, number),
  constraint invoice_period_is_first_of_month
    check (period_month = date_trunc('month', period_month)::date),
  -- A draft may be discarded, so it gets no number; anything that has left
  -- draft must have one, including a void invoice (the number stays burnt,
  -- which is what keeps the sequence gapless).
  constraint invoice_numbered_once_issued
    check ((status = 'draft') = (number is null)),
  constraint invoice_issued_at_set
    check ((status = 'draft') = (issued_at is null))
);

create index invoice_member_idx on public.invoice (member_id, period_month desc);

create trigger invoice_set_updated_at
  before update on public.invoice
  for each row execute function public.set_updated_at();

-- Gapless numbering.
--
-- A Postgres sequence is the wrong tool: nextval() does not roll back, so an
-- abandoned transaction burns a number and GST invoices must not have gaps. A
-- counter row does roll back, and the UPDATE takes a row lock that serialises
-- two admins closing the month at the same moment.
create table public.invoice_counter (
  company_id  uuid primary key references public.company(id) on delete cascade,
  next_number bigint not null default 1
);

create function public.next_invoice_number(p_company_id uuid)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_number bigint;
begin
  insert into public.invoice_counter (company_id)
  values (p_company_id)
  on conflict (company_id) do nothing;

  update public.invoice_counter
     set next_number = next_number + 1
   where company_id = p_company_id
  returning next_number - 1 into v_number;

  return v_number;
end;
$$;

-- ---------------------------------------------------------------------------
-- The ledger
--
-- SIGN CONVENTION, which everything else depends on:
--
--   positive = the member owes the company more
--   negative = the member owes the company less
--
-- So charges are positive; a payment or an approved expense credit is
-- negative; and a payout is POSITIVE, because cash leaving the company to the
-- member settles a credit balance and brings it back toward zero. Getting
-- payout backwards would double-count every reimbursement, so the sign is
-- pinned per kind by a check constraint rather than left to calling code.
-- ---------------------------------------------------------------------------

create table public.ledger_entry (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references public.company(id) on delete restrict,
  member_id       uuid not null references public.member(id) on delete restrict,
  -- null for anything that is not a line of an invoice: payments, payouts,
  -- and adjustments raised between closes.
  invoice_id      uuid references public.invoice(id) on delete restrict,
  kind            public.ledger_entry_kind not null,
  entry_date      date not null,
  description     text not null,
  -- Kept for the "12.4 hr x $285.00" line the review step has to show.
  quantity        numeric(10,2),
  unit_rate       numeric(10,4),
  amount          numeric(12,2) not null,
  gst_amount      numeric(12,2) not null default 0,
  tax_treatment   public.tax_treatment not null default 'out_of_scope',
  gl_account_code text not null,
  external_ref    text,
  synced_at       timestamptz,
  created_at      timestamptz not null default now(),

  -- The account must exist in the company's own chart, or the journal export
  -- would emit a line no accounting system can accept.
  foreign key (company_id, gl_account_code)
    references public.gl_account (company_id, code) on delete restrict,

  constraint ledger_entry_sign_matches_kind check (
    case kind
      when 'flight_charge'  then amount > 0
      when 'hangarage'      then amount > 0
      when 'insurance'      then amount > 0
      when 'expense_credit' then amount < 0
      when 'payment'        then amount < 0
      when 'payout'         then amount > 0
      when 'adjustment'     then amount <> 0
    end
  ),
  -- GST follows the charge: it cannot be claimed on a line that carries no tax,
  -- and it must push the balance the same way the charge does.
  constraint ledger_entry_gst_only_when_taxable
    check (gst_amount = 0 or tax_treatment = 'taxable'),
  constraint ledger_entry_gst_follows_amount
    check (gst_amount = 0 or sign(gst_amount) = sign(amount))
);

create index ledger_entry_member_idx on public.ledger_entry (member_id, entry_date desc);
create index ledger_entry_invoice_idx on public.ledger_entry (invoice_id);

-- ---------------------------------------------------------------------------
-- Balances
--
-- A draft invoice is a proposal, not a debt, so its lines are excluded until
-- the invoice is issued. A void invoice never counts. Payments and ad-hoc
-- adjustments have no invoice and always count.
-- ---------------------------------------------------------------------------

-- security_invoker is not the default and must be stated. Without it a view
-- runs as its owner, which is the table owner, which bypasses RLS entirely --
-- so every pilot would read every other pilot's ledger through the view.
create view public.ledger_entry_posted
with (security_invoker = on) as
  select e.*
  from public.ledger_entry e
  left join public.invoice i on i.id = e.invoice_id
  where e.invoice_id is null
     or i.status in ('issued', 'settled');

-- Not security definer, so it is filtered by the caller's RLS: a pilot asking
-- for another member's balance gets 0 rather than the figure. The app only
-- ever asks for the current member, and an admin sees everyone.
create function public.member_balance(p_member_id uuid)
returns numeric
language sql
stable
as $$
  select coalesce(sum(amount + gst_amount), 0)::numeric(12,2)
  from public.ledger_entry_posted
  where member_id = p_member_id;
$$;

create function public.invoice_total(p_invoice_id uuid)
returns numeric
language sql
stable
as $$
  select coalesce(sum(amount + gst_amount), 0)::numeric(12,2)
  from public.ledger_entry
  where invoice_id = p_invoice_id;
$$;

-- ---------------------------------------------------------------------------
-- Immutability
--
-- SPEC.md 4.6: "a sent invoice never changes silently. Later hand-edits
-- become adjustment lines on the next bill." Enforced in the database, not in
-- the app, because Server Actions are public POST endpoints.
-- ---------------------------------------------------------------------------

create function public.guard_invoice_immutable()
returns trigger
language plpgsql
as $$
begin
  if old.status = 'draft' then
    return new;
  end if;

  -- Past draft, only the status may advance and only the sync fields may be
  -- written. Everything else is frozen.
  if (new.company_id,   new.member_id, new.period_month,
      new.number,       new.issued_at, new.note)
     is distinct from
     (old.company_id,   old.member_id, old.period_month,
      old.number,       old.issued_at, old.note)
  then
    raise exception
      'invoice % is % and cannot be edited; raise an adjustment instead',
      old.id, old.status;
  end if;

  if new.status <> old.status
     and not (old.status = 'issued' and new.status in ('settled', 'void'))
  then
    raise exception 'invoice % cannot move from % to %',
      old.id, old.status, new.status;
  end if;

  return new;
end;
$$;

create trigger invoice_guard_immutable
  before update on public.invoice
  for each row execute function public.guard_invoice_immutable();

create function public.guard_invoice_delete()
returns trigger
language plpgsql
as $$
begin
  if old.status <> 'draft' then
    raise exception 'invoice % is % and cannot be deleted; void it instead',
      old.id, old.status;
  end if;
  return old;
end;
$$;

create trigger invoice_guard_delete
  before delete on public.invoice
  for each row execute function public.guard_invoice_delete();

create function public.guard_ledger_entry_immutable()
returns trigger
language plpgsql
as $$
declare
  v_invoice uuid;
  v_status  public.invoice_status;
begin
  -- NEW is unassigned in a DELETE trigger, so it cannot be touched before
  -- tg_op has been checked. The OLD row's invoice is what decides either way,
  -- so a line cannot be detached from an issued invoice and then edited.
  if tg_op = 'DELETE' then
    v_invoice := old.invoice_id;
  else
    v_invoice := coalesce(old.invoice_id, new.invoice_id);
  end if;

  select i.status into v_status
  from public.invoice i
  where i.id = v_invoice;

  if v_status is null or v_status = 'draft' then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  -- Past draft the line is frozen, except for the sync fields, which are
  -- written after issuing by definition.
  if tg_op = 'UPDATE'
     and (new.id, new.company_id, new.member_id, new.invoice_id, new.kind,
          new.entry_date, new.description, new.quantity, new.unit_rate,
          new.amount, new.gst_amount, new.tax_treatment, new.gl_account_code)
         is not distinct from
         (old.id, old.company_id, old.member_id, old.invoice_id, old.kind,
          old.entry_date, old.description, old.quantity, old.unit_rate,
          old.amount, old.gst_amount, old.tax_treatment, old.gl_account_code)
  then
    return new;
  end if;

  raise exception
    'ledger entry % belongs to a % invoice and cannot be changed', old.id, v_status;
end;
$$;

create trigger ledger_entry_guard_immutable
  before update or delete on public.ledger_entry
  for each row execute function public.guard_ledger_entry_immutable();

-- An invoice line must belong to the member the invoice was raised for, and to
-- the same company. Nothing in the schema would otherwise stop one pilot's
-- charge landing on another pilot's bill.
create function public.assert_ledger_entry_matches_invoice()
returns trigger
language plpgsql
as $$
declare
  v_member  uuid;
  v_company uuid;
begin
  if new.invoice_id is null then
    return new;
  end if;

  select i.member_id, i.company_id into v_member, v_company
  from public.invoice i where i.id = new.invoice_id;

  if v_member <> new.member_id or v_company <> new.company_id then
    raise exception
      'ledger entry for member %/company % cannot be a line of invoice % (member %/company %)',
      new.member_id, new.company_id, new.invoice_id, v_member, v_company;
  end if;

  return new;
end;
$$;

create trigger ledger_entry_matches_invoice
  before insert or update on public.ledger_entry
  for each row execute function public.assert_ledger_entry_matches_invoice();

-- ---------------------------------------------------------------------------
-- General ledger journal
--
-- The export surface for an accounting system: one balanced pair of rows per
-- ledger entry. Charges debit receivables and credit the revenue account the
-- line maps to; a payment debits the bank and credits receivables.
--
-- Only posted entries appear, so a draft month is never exported.
-- ---------------------------------------------------------------------------

create view public.gl_journal
with (security_invoker = on) as
with entry as (
  select
    e.id,
    e.company_id,
    e.member_id,
    e.entry_date,
    e.kind,
    e.description,
    e.tax_treatment,
    e.gl_account_code,
    e.amount + e.gst_amount as gross,
    c.ar_account_code,
    c.bank_account_code,
    i.number as invoice_number
  from public.ledger_entry_posted e
  join public.company c on c.id = e.company_id
  left join public.invoice i on i.id = e.invoice_id
)
-- The receivable side. Payments and payouts move cash, so their counter-account
-- is the bank; everything else is a charge or credit against the member.
select
  e.id            as ledger_entry_id,
  e.company_id,
  e.member_id,
  e.entry_date,
  e.invoice_number,
  e.kind,
  e.description,
  1               as line_no,
  case when e.kind in ('payment', 'payout')
       then e.bank_account_code else e.ar_account_code end as gl_account_code,
  case when e.kind in ('payment', 'payout')
       then -e.gross else e.gross end as debit_credit,
  'out_of_scope'::public.tax_treatment as tax_treatment
from entry e
union all
select
  e.id,
  e.company_id,
  e.member_id,
  e.entry_date,
  e.invoice_number,
  e.kind,
  e.description,
  2,
  case when e.kind in ('payment', 'payout')
       then e.ar_account_code else e.gl_account_code end,
  case when e.kind in ('payment', 'payout')
       then e.gross else -e.gross end,
  e.tax_treatment
from entry e;

comment on view public.gl_journal is
  'Balanced double-entry lines for export to an accounting system. debit_credit is positive for a debit, negative for a credit; the two lines of a ledger entry always sum to zero.';

-- ---------------------------------------------------------------------------
-- Row level security
--
-- SPEC.md 4.6: "Only an admin sees all pilots' numbers." A pilot sees their
-- own ledger and invoices and nobody else's. Pilots never write money rows at
-- all: charges are generated by closing a month, and payments are recorded by
-- an admin.
-- ---------------------------------------------------------------------------

alter table public.gl_account           enable row level security;
alter table public.rate_schedule        enable row level security;
alter table public.rate_component       enable row level security;
alter table public.fixed_cost_schedule  enable row level security;
alter table public.fixed_cost           enable row level security;
alter table public.invoice              enable row level security;
alter table public.invoice_counter      enable row level security;
alter table public.ledger_entry         enable row level security;

revoke all on public.gl_account          from anon;
revoke all on public.rate_schedule       from anon;
revoke all on public.rate_component      from anon;
revoke all on public.fixed_cost_schedule from anon;
revoke all on public.fixed_cost          from anon;
revoke all on public.invoice             from anon;
revoke all on public.invoice_counter     from anon;
revoke all on public.ledger_entry        from anon;
revoke all on public.ledger_entry_posted from anon;
revoke all on public.gl_journal          from anon;

-- Rates and the chart of accounts are shared configuration: every owner may
-- read them (the Pool page shows the rate breakdown), only an admin may change
-- them, and a change is a new schedule rather than an edit.
create policy gl_account_select_members on public.gl_account
  for select to authenticated using (public.current_member_id() is not null);
create policy gl_account_admin_write on public.gl_account
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy rate_schedule_select_members on public.rate_schedule
  for select to authenticated using (public.current_member_id() is not null);
create policy rate_schedule_admin_write on public.rate_schedule
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy rate_component_select_members on public.rate_component
  for select to authenticated using (public.current_member_id() is not null);
create policy rate_component_admin_write on public.rate_component
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy fixed_cost_schedule_select_members on public.fixed_cost_schedule
  for select to authenticated using (public.current_member_id() is not null);
create policy fixed_cost_schedule_admin_write on public.fixed_cost_schedule
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy fixed_cost_select_members on public.fixed_cost
  for select to authenticated using (public.current_member_id() is not null);
create policy fixed_cost_admin_write on public.fixed_cost
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Money: own rows only, unless admin.
create policy invoice_select_own on public.invoice
  for select to authenticated using (member_id = public.current_member_id());
create policy invoice_admin_all on public.invoice
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy ledger_entry_select_own on public.ledger_entry
  for select to authenticated using (member_id = public.current_member_id());
create policy ledger_entry_admin_all on public.ledger_entry
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- The counter is allocated through next_invoice_number(), which is security
-- definer. Nothing reads or writes the table directly, so no policy is granted
-- and RLS denies everyone by default.

-- Views do not have policies of their own; they run with the privileges of the
-- querying user, so the policies above still apply through them.
grant select on public.ledger_entry_posted to authenticated;
grant select on public.gl_journal to authenticated;
