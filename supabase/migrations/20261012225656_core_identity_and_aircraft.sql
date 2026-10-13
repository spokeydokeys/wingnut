-- Core identity, ownership and aircraft configuration.
--
-- PORTABILITY: this is plain PostgreSQL. The only Supabase-specific surface is
-- auth.uid(), used inside the two RLS helper functions below, and the loose
-- member.auth_user_id -> auth.users(id) reference (deliberately not a foreign
-- key, so the auth provider can be swapped). Moving to self-hosted Postgres
-- means replacing two functions, not rewriting the schema.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

create type public.member_role as enum ('pilot', 'admin');

-- Billing is on flight time (spec 4.1). Tach is tracked but only drives
-- engine/prop life, never money.
create type public.billing_basis as enum ('flight_time', 'tach');

create type public.fixed_cost_split as enum ('ownership_pct', 'equal', 'hours_flown');

create type public.hour_rounding as enum ('round_up_tenth', 'nearest_tenth', 'exact');

create type public.expense_approval_rule as enum ('any_other_owner', 'admin_only');

-- ---------------------------------------------------------------------------
-- Shared trigger helpers
-- ---------------------------------------------------------------------------

create function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- company
--
-- The aircraft is owned through a BC company, and the company (not the
-- aircraft) is what issues invoices. CRA requires an invoice to carry the
-- supplier's legal name and, when registered, the GST number, so these live
-- here rather than on the aircraft.
-- ---------------------------------------------------------------------------

create table public.company (
  id                    uuid primary key default gen_random_uuid(),
  legal_name            text not null check (length(trim(legal_name)) > 0),
  gst_registered        boolean not null default false,
  gst_number            text,
  -- Month the fiscal year ends (1-12), needed to scope year-end reporting.
  fiscal_year_end_month smallint not null default 12
                          check (fiscal_year_end_month between 1 and 12),
  etransfer_recipient   text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create trigger company_set_updated_at
  before update on public.company
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- member
-- ---------------------------------------------------------------------------

create table public.member (
  id           uuid primary key default gen_random_uuid(),
  -- Maps to the auth provider's user id. Nullable so a member can be created
  -- before they have ever signed in.
  auth_user_id uuid unique,
  full_name    text not null check (length(trim(full_name)) > 0),
  email        text not null check (position('@' in email) > 1),
  role         public.member_role not null default 'pilot',
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create unique index member_email_lower_key on public.member (lower(email));

create trigger member_set_updated_at
  before update on public.member
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- aircraft
-- ---------------------------------------------------------------------------

create table public.aircraft (
  id                      uuid primary key default gen_random_uuid(),
  company_id              uuid not null references public.company(id) on delete restrict,
  registration            text not null unique check (length(trim(registration)) > 0),
  nickname                text,
  billing_basis           public.billing_basis not null default 'flight_time',

  -- Estimated tach = flight_time / tach_factor. Direction confirmed with the
  -- owner on 12 Oct 2026: tach runs SLOWER than the clock, so this divides.
  -- At the default 1.3, 0:48 of flight time is 0.6 tach.
  tach_factor             numeric(5,3) not null default 1.300 check (tach_factor > 0),

  -- Drives accrual for calendar-limited items such as the 2034 prop overhaul.
  expected_hours_per_year numeric(6,1) check (expected_hours_per_year > 0),

  fixed_cost_split        public.fixed_cost_split not null default 'ownership_pct',
  billed_hour_rounding    public.hour_rounding not null default 'round_up_tenth',
  expense_approval_rule   public.expense_approval_rule not null default 'any_other_owner',

  -- Radius for matching a GPS fix to a known place (spec 4.2).
  place_match_radius_m    integer not null default 1000 check (place_match_radius_m > 0),

  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

create index aircraft_company_id_idx on public.aircraft (company_id);

create trigger aircraft_set_updated_at
  before update on public.aircraft
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Ownership, effective-dated
--
-- Ownership is stored as complete snapshots rather than as a percentage column
-- on each member. When owners join or leave you insert a new period holding
-- every owner's share, so a month closed under the old split keeps billing
-- under the old split. Without this, adding an owner would silently rewrite
-- past invoices, which spec 4.6 forbids.
--
-- A period runs from its effective_from until the next period's effective_from.
-- ---------------------------------------------------------------------------

create table public.ownership_period (
  id             uuid primary key default gen_random_uuid(),
  aircraft_id    uuid not null references public.aircraft(id) on delete cascade,
  effective_from date not null,
  note           text,
  created_at     timestamptz not null default now(),
  unique (aircraft_id, effective_from)
);

create table public.ownership_share (
  period_id uuid not null references public.ownership_period(id) on delete cascade,
  member_id uuid not null references public.member(id) on delete restrict,
  -- 0 is legal and means that member had exited as of this period.
  pct       numeric(7,4) not null check (pct >= 0 and pct <= 100),
  primary key (period_id, member_id)
);

create index ownership_share_member_id_idx on public.ownership_share (member_id);

-- Shares in a period must account for exactly 100%. Deferred to the end of the
-- transaction because the rows are inserted one at a time.
create function public.assert_ownership_sums_to_100()
returns trigger
language plpgsql
as $$
declare
  v_period uuid := coalesce(new.period_id, old.period_id);
  v_total  numeric(9,4);
begin
  select coalesce(sum(pct), 0) into v_total
  from public.ownership_share
  where period_id = v_period;

  -- A total of 0 means every share was removed, which is how a period is deleted.
  if v_total <> 0 and v_total <> 100 then
    raise exception
      'ownership shares for period % sum to %, must be 100', v_period, v_total;
  end if;

  return null;
end;
$$;

create constraint trigger ownership_share_sums_to_100
  after insert or update or delete on public.ownership_share
  deferrable initially deferred
  for each row execute function public.assert_ownership_sums_to_100();

-- Resolves who owned what on a given date. Billing calls this with the first
-- day of the period being closed.
create function public.ownership_as_of(p_aircraft_id uuid, p_on date)
returns table (member_id uuid, pct numeric)
language sql
stable
as $$
  select s.member_id, s.pct
  from public.ownership_period p
  join public.ownership_share s on s.period_id = p.id
  where p.aircraft_id = p_aircraft_id
    and p.effective_from = (
      select max(p2.effective_from)
      from public.ownership_period p2
      where p2.aircraft_id = p_aircraft_id
        and p2.effective_from <= p_on
    );
$$;

-- ---------------------------------------------------------------------------
-- RLS helpers
--
-- security definer so they can read public.member without being gated by the
-- very policies they are used in, which would recurse. search_path is pinned to
-- empty to prevent search_path hijacking, which is why every identifier and
-- enum literal below is fully qualified.
-- ---------------------------------------------------------------------------

create function public.current_member_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.id
  from public.member m
  where m.auth_user_id = auth.uid()
    and m.is_active
  limit 1;
$$;

create function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.member m
    where m.auth_user_id = auth.uid()
      and m.is_active
      and m.role = 'admin'::public.member_role
  );
$$;

-- A member may edit their own profile, but must not be able to promote
-- themselves to admin or re-point their auth mapping at someone else. RLS
-- cannot restrict individual columns, so this is enforced here.
create function public.guard_member_privileged_columns()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role is distinct from old.role and not public.is_admin() then
    raise exception 'only an admin may change a member role';
  end if;

  if new.auth_user_id is distinct from old.auth_user_id and not public.is_admin() then
    raise exception 'only an admin may change the auth mapping';
  end if;

  if new.is_active is distinct from old.is_active and not public.is_admin() then
    raise exception 'only an admin may activate or deactivate a member';
  end if;

  return new;
end;
$$;

create trigger member_guard_privileged_columns
  before update on public.member
  for each row execute function public.guard_member_privileged_columns();

-- ---------------------------------------------------------------------------
-- Row level security
--
-- Co-owners are a small trusted group and need to see each other to make
-- bookings and to approve each other's expenses, so reads are open to any
-- active member. Writes to shared configuration are admin-only. Money tables
-- arrive in a later migration and are scoped per member there.
-- ---------------------------------------------------------------------------

alter table public.company          enable row level security;
alter table public.member           enable row level security;
alter table public.aircraft         enable row level security;
alter table public.ownership_period enable row level security;
alter table public.ownership_share  enable row level security;

-- Defence in depth: the anon role should never touch these, policy aside.
revoke all on public.company          from anon;
revoke all on public.member           from anon;
revoke all on public.aircraft         from anon;
revoke all on public.ownership_period from anon;
revoke all on public.ownership_share  from anon;

create policy company_select_members on public.company
  for select to authenticated
  using (public.current_member_id() is not null);

create policy company_admin_write on public.company
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy member_select_members on public.member
  for select to authenticated
  using (public.current_member_id() is not null);

create policy member_update_self on public.member
  for update to authenticated
  using (id = public.current_member_id())
  with check (id = public.current_member_id());

create policy member_admin_write on public.member
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy aircraft_select_members on public.aircraft
  for select to authenticated
  using (public.current_member_id() is not null);

create policy aircraft_admin_write on public.aircraft
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy ownership_period_select_members on public.ownership_period
  for select to authenticated
  using (public.current_member_id() is not null);

create policy ownership_period_admin_write on public.ownership_period
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy ownership_share_select_members on public.ownership_share
  for select to authenticated
  using (public.current_member_id() is not null);

create policy ownership_share_admin_write on public.ownership_share
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
