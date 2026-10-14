-- ---------------------------------------------------------------------------
-- Ownership is held in shares, not in percent
--
-- The company has a fixed number of shares -- 1200, chosen because it divides
-- by 2, 3, 4, 6 and 8 -- and an owner holds a whole number of them. Percent
-- could not say that: three owners are 33.3333% each, which sums to 99.9999%,
-- so either the constraint has to tolerate a gap or one owner has to carry a
-- rounding crumb that is visible on every invoice forever.
--
-- Shares make the awkward splits exact. 1200/3 = 400. 1200/8 = 150. The
-- fraction is still a fraction when it is divided out for money, but the thing
-- that is STORED, constrained and shown to people is an integer that adds up.
--
-- The share count lives on the company because that is what is owned; the
-- aircraft is an asset of it. ownership_period stays keyed on the aircraft, so
-- a second aeroplane in the same company could one day have its own history.
-- ---------------------------------------------------------------------------

alter table public.company
  add column total_shares integer not null default 1200
    check (total_shares > 0);

comment on column public.company.total_shares is
  'Shares the company is divided into. Every ownership_period must allocate '
  'exactly this many. Changing it would invalidate every period, so it is set '
  'once at incorporation.';

-- The split setting named the unit, and the unit has changed. Renaming the
-- label rather than adding one keeps a single truth: there is no moment where
-- both exist and a reader has to work out which is live.
alter type public.fixed_cost_split rename value 'ownership_pct' to 'ownership_shares';

-- ---------------------------------------------------------------------------
-- pct -> shares
-- ---------------------------------------------------------------------------

-- Dropped before the backfill so the old assertion is not checking a column
-- that is on its way out.
drop trigger ownership_share_sums_to_100 on public.ownership_share;
drop function public.assert_ownership_sums_to_100();

alter table public.ownership_share add column shares integer;

update public.ownership_share s
   set shares = round(s.pct / 100 * c.total_shares)
  from public.ownership_period p
  join public.aircraft a on a.id = p.aircraft_id
  join public.company c   on c.id = a.company_id
 where p.id = s.period_id;

alter table public.ownership_share
  alter column shares set not null,
  add constraint ownership_share_shares_nonneg check (shares >= 0),
  drop column pct;

comment on column public.ownership_share.shares is
  'Whole shares held in this period. 0 is legal and means that member had '
  'exited as of this period.';

-- Same shape as before: the shares in a period must account for exactly the
-- company''s total. Deferred to the end of the transaction because the rows are
-- inserted one at a time, and re-splitting four ways is four inserts that are
-- only balanced once they are all in.
create function public.assert_ownership_sums_to_total()
returns trigger
language plpgsql
as $$
declare
  v_period uuid := coalesce(new.period_id, old.period_id);
  v_total  bigint;
  v_want   integer;
begin
  select c.total_shares into v_want
  from public.ownership_period p
  join public.aircraft a on a.id = p.aircraft_id
  join public.company c   on c.id = a.company_id
  where p.id = v_period;

  -- The period itself has been deleted and took its shares with it.
  if v_want is null then
    return null;
  end if;

  select coalesce(sum(s.shares), 0) into v_total
  from public.ownership_share s
  where s.period_id = v_period;

  -- A total of 0 means every share was removed, which is how a period is
  -- emptied before it is deleted.
  if v_total <> 0 and v_total <> v_want then
    raise exception
      'ownership shares for period % sum to %, must be %',
      v_period, v_total, v_want;
  end if;

  return null;
end;
$$;

create constraint trigger ownership_share_sums_to_total
  after insert or update or delete on public.ownership_share
  deferrable initially deferred
  for each row execute function public.assert_ownership_sums_to_total();

-- ---------------------------------------------------------------------------
-- Resolving ownership on a date
--
-- Now returns the shares, the denominator they are out of, AND the fraction
-- they work out to. The fraction is computed here rather than at each call
-- site so that nobody has to remember the denominator -- the old signature
-- returned a percent and every caller divided it by 100 itself, which is one
-- forgotten division away from billing a member 50 times the hangarage.
-- ---------------------------------------------------------------------------

drop function public.ownership_as_of(uuid, date);

create function public.ownership_as_of(p_aircraft_id uuid, p_on date)
returns table (
  member_id    uuid,
  shares       integer,
  total_shares integer,
  fraction     numeric
)
language sql
stable
as $$
  select s.member_id, s.shares, c.total_shares,
         s.shares::numeric / c.total_shares
  from public.ownership_period p
  join public.ownership_share s on s.period_id = p.id
  join public.aircraft a on a.id = p.aircraft_id
  join public.company c   on c.id = a.company_id
  where p.aircraft_id = p_aircraft_id
    and p.effective_from = (
      select max(p2.effective_from)
      from public.ownership_period p2
      where p2.aircraft_id = p_aircraft_id
        and p2.effective_from <= p_on
    );
$$;

-- ---------------------------------------------------------------------------
-- The two functions that priced ownership in percent
-- ---------------------------------------------------------------------------

create or replace function public.fixed_cost_share(
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

  if v_split = 'ownership_shares' then
    select o.fraction into v_share
    from public.ownership_as_of(p_aircraft_id, v_start) o
    where o.member_id = p_member_id;

  elsif v_split = 'equal' then
    -- Among the owners of record that month, not among everyone on the roster:
    -- an owner who has exited holds 0 shares and does not pay hangarage.
    select case when count(*) = 0 then null else 1.0 / count(*) end
      into v_share
    from public.ownership_as_of(p_aircraft_id, v_start) o
    where o.shares > 0
      and exists (
        select 1 from public.ownership_as_of(p_aircraft_id, v_start) mine
        where mine.member_id = p_member_id and mine.shares > 0
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
 * Replaced only to say the share in the units it is held in.
 *
 * The fixed-cost line read "Hangarage · 33.33% share", which is a rounding of
 * 400/1200 -- and three owners holding a third each can put their three
 * invoices side by side and add up 99.99%. "400 of 1200 shares" is the figure
 * that was actually voted on, and it adds up. The arithmetic below is
 * unchanged: money is still the exact fraction times the cost.
 *
 * The other two splits keep the percent, because there is no share count
 * behind them -- an equal split of three really is 33.33%.
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
  v_held     text;
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

  select format('%s of %s shares', o.shares, o.total_shares)
    into v_held
  from public.ownership_as_of(p_aircraft_id, v_start) o
  where o.member_id = p_member_id
    and (select a.fixed_cost_split from public.aircraft a where a.id = p_aircraft_id)
        = 'ownership_shares';

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
    format('%s · %s', fc.name,
           coalesce(v_held,
                    trim(to_char(v_share * 100, 'FM999990.##')) || '% share')),
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
