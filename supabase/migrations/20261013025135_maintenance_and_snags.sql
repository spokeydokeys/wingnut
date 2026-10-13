-- Snags, maintenance items and tach readings: the Aircraft tab.
--
-- Three ideas carry this migration.
--
-- 1. The TACH IS AN ESTIMATE between readings. Nothing in this app watches the
--    hour meter; it watches the clock. So `aircraft_tach_estimate` is the last
--    real reading plus the estimated tach of every flight since, and a reading
--    logged today resets that running total to the truth (SPEC.md 4.4: "the app
--    resets its running estimate to match"). Maintenance due-dates therefore
--    move the moment a reading is logged, which is the correct behaviour and the
--    reason the estimate is a function rather than a stored column.
--
-- 2. "Last done" is NOT a column on maintenance_item. SPEC.md 4.4 asks for both
--    a last-done date/tach and a log of who marked it done, and storing the same
--    fact twice means one of them is eventually wrong. The log is the truth and
--    the last-done values are read off its newest row -- which also means
--    correcting a mis-entered grease job fixes the counter for free. The opening
--    state at handover is itself an event, seeded as such.
--
-- 3. Status is DERIVED, in one place. `maintenance_status` turns intervals,
--    leads and the tach estimate into hours or days remaining, a fraction for
--    the progress bar, and a text state. SPEC.md 4.4 insists on "a progress bar
--    plus a text status (never colour alone)", so the state is a word the UI
--    prints, not a colour it picks.
--
-- Deliberately NOT here:
--   - Snag photos (SPEC.md 4.3). They need object storage, and portability
--     means storing bucket keys rather than signed URLs. That is its own piece
--     of work and a snag with no photo is still a useful snag.
--   - The "suggest updating the tach factor" hint (SPEC.md 4.4). The observed
--     ratio needs two readings with flights between them, which no real data
--     has yet, and the hint belongs next to the factor setting in admin.

create type public.snag_status as enum ('open', 'watch', 'cleared');

-- Why the item exists, which decides what "done" means. A life limit is reached
-- once and then the part is overhauled or replaced; the other two recur.
create type public.maintenance_kind as enum
  ('life_limit', 'recurring_inspection', 'recurring_task');

-- What the interval is measured in. SPEC.md 4.4: engine and grease run on tach,
-- prop overhaul and blade clip on the calendar.
create type public.maintenance_basis as enum ('tach', 'calendar');

-- Where a tach reading came from. 'flight' rows are written by the trigger
-- below from a pilot's Confirm-screen entry; 'manual' is the Log tach reading
-- button, which needs no flight.
create type public.tach_reading_source as enum ('manual', 'flight');

-- ---------------------------------------------------------------------------
-- What day it is where the aeroplane is
--
-- `current_date` is today in the DATABASE's zone, which on managed Postgres is
-- UTC. From 5pm Pacific onwards that is already tomorrow, so every calendar
-- item would silently come due a day early each evening -- the blade clip would
-- read "41 days" over lunch and "40 days" after dinner.
--
-- The pair of this is AIRCRAFT_TIME_ZONE in lib/time.ts. One aeroplane, one
-- zone, named in both languages.
-- ---------------------------------------------------------------------------

create function public.aircraft_today() returns date
  language sql stable set search_path = '' as $$
  select (now() at time zone 'America/Vancouver')::date;
$$;

comment on function public.aircraft_today() is
  'Today in the aeroplane''s time zone, not the database''s.';

-- ---------------------------------------------------------------------------
-- Snags
--
-- SPEC.md 4.3. `grounding` is its own flag rather than a fourth status because
-- it is orthogonal: a grounding snag is an open snag with teeth, and a watch
-- item never grounds.
-- ---------------------------------------------------------------------------

create table public.snag (
  id          uuid primary key default gen_random_uuid(),
  aircraft_id uuid not null references public.aircraft(id) on delete cascade,
  title       text not null check (length(trim(title)) > 0),
  status      public.snag_status not null default 'open',
  grounding   boolean not null default false,
  notes       text,

  reported_by uuid references public.member(id) on delete set null,
  reported_at timestamptz not null default now(),

  -- Set when the snag was noticed on a particular flight (SPEC.md 4.3: "can be
  -- added from the Confirm screen after a flight"). set null on delete: a
  -- cancelled flight must not take the snag with it.
  flight_id   uuid references public.flight(id) on delete set null,

  cleared_at  timestamptz,
  cleared_by  uuid references public.member(id) on delete set null,

  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  -- Cleared and clearing time move together, so a list can trust either one.
  constraint snag_cleared_has_timestamp
    check ((status = 'cleared') = (cleared_at is not null))
);

create index snag_open_idx on public.snag (aircraft_id, reported_at desc)
  where status <> 'cleared';

create trigger snag_set_updated_at
  before update on public.snag
  for each row execute function public.set_updated_at();

-- Keeps the clearing fields in step with the status so no caller has to, which
-- is also what makes the check constraint above satisfiable from a one-field
-- form. Re-opening a snag forgets who cleared it, on purpose: that information
-- described a state the snag is no longer in.
create function public.snag_stamp_cleared()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'cleared' then
    -- Stamped on the TRANSITION only, and always from the database rather than
    -- from whatever the caller sent -- otherwise a crafted request could say
    -- someone else fixed the brake. Re-saving a cleared snag's notes keeps the
    -- original stamp.
    if tg_op = 'INSERT' or old.status is distinct from 'cleared' then
      new.cleared_at := now();
      new.cleared_by := public.current_member_id();
    else
      new.cleared_at := old.cleared_at;
      new.cleared_by := old.cleared_by;
    end if;
  else
    new.cleared_at := null;
    new.cleared_by := null;
  end if;
  return new;
end;
$$;

create trigger snag_stamp_cleared
  before insert or update on public.snag
  for each row execute function public.snag_stamp_cleared();

-- ---------------------------------------------------------------------------
-- Tach readings
--
-- SPEC.md 4.4: any pilot can log one. Readings are append-only history, not a
-- current-value column, because the whole point is to measure drift between
-- what the app estimated and what the meter says.
--
-- There is deliberately no "must be higher than the last one" constraint. A
-- tach only climbs in reality, but readings are typed by people and arrive out
-- of order -- backfilling last winter's logbook would be refused by a rule that
-- only looked at the newest row. A fat-fingered reading is visible on this
-- screen and fixable; a constraint that blocks correct data is not.
-- ---------------------------------------------------------------------------

create table public.tach_reading (
  id          uuid primary key default gen_random_uuid(),
  aircraft_id uuid not null references public.aircraft(id) on delete cascade,
  reading     numeric(10,2) not null check (reading >= 0),
  -- When the meter was read, not when the row was written: a flight confirmed
  -- the next morning carries the previous evening's reading.
  read_at     timestamptz not null default now(),
  read_by     uuid references public.member(id) on delete set null,
  source      public.tach_reading_source not null default 'manual',

  -- The flight whose actual_tach_hours produced this row, if any.
  flight_id   uuid references public.flight(id) on delete cascade,

  note        text,
  created_at  timestamptz not null default now(),

  constraint tach_reading_flight_matches_source
    check ((source = 'flight') = (flight_id is not null))
);

create index tach_reading_latest_idx
  on public.tach_reading (aircraft_id, read_at desc, created_at desc);

-- One reading per flight, which is what lets the trigger below upsert rather
-- than accumulate a row every time a pilot re-saves the Confirm screen.
create unique index tach_reading_one_per_flight
  on public.tach_reading (flight_id) where flight_id is not null;

-- ---------------------------------------------------------------------------
-- A flight's tach entry IS a tach reading
--
-- The Confirm screen already asks for "actual tach reading (optional)". Without
-- this trigger that field would be a dead end -- stored on the flight, invisible
-- to maintenance -- and a pilot who typed it would then be asked for it again
-- under Log tach reading. One source of truth, written from the flight.
--
-- read_at is the flight's END, which also keeps the flight out of its own
-- estimate: aircraft_tach_estimate only adds flights that started after the
-- reading, and a flight starts before it ends.
-- ---------------------------------------------------------------------------

create function public.flight_sync_tach_reading()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.actual_tach_hours is null then
    -- The pilot cleared the field; the reading it stood for no longer exists.
    delete from public.tach_reading where flight_id = new.id;
    return null;
  end if;

  insert into public.tach_reading
    (aircraft_id, reading, read_at, read_by, source, flight_id)
  values
    (new.aircraft_id, new.actual_tach_hours, coalesce(new.end_at, new.start_at),
     new.pilot_member_id, 'flight', new.id)
  on conflict (flight_id) where flight_id is not null do update
    set aircraft_id = excluded.aircraft_id,
        reading     = excluded.reading,
        read_at     = excluded.read_at,
        read_by     = excluded.read_by;

  return null;
end;
$$;

create trigger flight_sync_tach_reading
  after insert or update of actual_tach_hours, start_at, end_at, aircraft_id,
    pilot_member_id on public.flight
  for each row execute function public.flight_sync_tach_reading();

-- ---------------------------------------------------------------------------
-- The running tach estimate
--
-- Null when the aeroplane has never had a reading logged, and the screens say
-- so rather than guessing: without a datum there is no tach, only a duration.
--
-- Flights still running have no est_tach_hours (flight_compute_hours nulls it),
-- so they are excluded by the is-not-null test rather than by a status check --
-- a stopped-but-unconfirmed draft has really been flown and its hours are on
-- the engine whether or not anyone has pressed Save yet.
-- ---------------------------------------------------------------------------

create function public.aircraft_tach_estimate(p_aircraft_id uuid)
returns numeric
language sql
stable
set search_path = ''
as $$
  with latest as (
    select r.reading, r.read_at
    from public.tach_reading r
    where r.aircraft_id = p_aircraft_id
    order by r.read_at desc, r.created_at desc
    limit 1
  )
  select round(l.reading + coalesce((
    select sum(f.est_tach_hours)
    from public.flight f
    where f.aircraft_id = p_aircraft_id
      and f.est_tach_hours is not null
      and f.start_at > l.read_at
  ), 0), 2)
  from latest l;
$$;

comment on function public.aircraft_tach_estimate is
  'Last logged tach reading plus the estimated tach of every flight since. Null until a first reading exists.';

-- ---------------------------------------------------------------------------
-- Maintenance items
--
-- One table with a kind and a basis (SPEC.md 4.4: "rather than forcing
-- everything into the reserve model"), holding the four real items.
--
-- `due_date` is for a calendar limit with no recurrence -- the 2034 prop
-- overhaul is a date, not an interval, and nobody knows what fraction of its
-- life is used, so that item shows a date and no progress bar.
-- ---------------------------------------------------------------------------

create table public.maintenance_item (
  id              uuid primary key default gen_random_uuid(),
  aircraft_id     uuid not null references public.aircraft(id) on delete cascade,
  name            text not null check (length(trim(name)) > 0),
  kind            public.maintenance_kind not null,
  basis           public.maintenance_basis not null,

  interval_hours  numeric(6,1) check (interval_hours > 0),
  interval_months integer check (interval_months > 0),
  -- A fixed calendar limit, used instead of interval_months.
  due_date        date,

  -- How much warning to give. SPEC.md 4.4's examples: grease at 22 of 25 hr
  -- (3 hr lead), blade clip 60 days out.
  lead_hours      numeric(6,1) check (lead_hours >= 0),
  lead_days       integer check (lead_days >= 0),

  est_cost        numeric(12,2) check (est_cost >= 0),

  sort_order      smallint not null default 0,
  is_active       boolean not null default true,

  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  -- The basis decides which interval columns mean anything, and an item with
  -- none of them can never come due -- which would be a silent failure, so it
  -- is a constraint instead.
  constraint maintenance_item_tach_has_hours
    check (basis <> 'tach' or interval_hours is not null),
  constraint maintenance_item_calendar_has_limit
    check (basis <> 'calendar' or interval_months is not null or due_date is not null)
);

create index maintenance_item_aircraft_idx
  on public.maintenance_item (aircraft_id, sort_order);

create trigger maintenance_item_set_updated_at
  before update on public.maintenance_item
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Marking an item done
--
-- SPEC.md 4.4: "Marking a task done logs who, when and tach, and resets its
-- counter." Both halves are this one row -- the counter resets because the
-- status view measures from the newest event, not because anything is updated.
--
-- `tach` is nullable so a calendar item (the blade clip) does not have to
-- invent one, and is defaulted from the estimate by the mark-done action for
-- the items where it matters.
--
-- No cost column: what a job actually cost is a receipt, and receipts are their
-- own phase with their own GST and charge-to rules (SPEC.md 4.7). A money field
-- here would be a second, quieter place for a bill to live.
-- ---------------------------------------------------------------------------

create table public.maintenance_event (
  id         uuid primary key default gen_random_uuid(),
  item_id    uuid not null references public.maintenance_item(id) on delete cascade,
  done_on    date not null default public.aircraft_today(),
  tach       numeric(10,2) check (tach >= 0),
  done_by    uuid references public.member(id) on delete set null,
  note       text,
  created_at timestamptz not null default now()
);

create index maintenance_event_item_idx
  on public.maintenance_event (item_id, done_on desc, created_at desc);

-- ---------------------------------------------------------------------------
-- Derived status
--
-- Everything the Aircraft tab needs per item, so the arithmetic is not repeated
-- in TypeScript. security_invoker so the view is read under the caller's own
-- policies rather than the view owner's.
--
-- fraction_used is clamped to 0..1: a bar cannot be 130% long, and "overdue" is
-- already said in words by `state`.
-- ---------------------------------------------------------------------------

create view public.maintenance_status
with (security_invoker = on) as
with measured as (
  select
    i.id,
    i.aircraft_id,
    i.name,
    i.kind,
    i.basis,
    i.interval_hours,
    i.interval_months,
    i.due_date,
    i.lead_hours,
    i.lead_days,
    i.est_cost,
    i.sort_order,
    e.done_on as last_done_on,
    e.tach    as last_done_tach,
    t.tach_now,
    case when i.basis = 'tach' then t.tach_now - e.tach end as hours_used,
    case when i.basis = 'tach'
         then i.interval_hours - (t.tach_now - e.tach) end as hours_remaining,
    case when i.basis = 'calendar'
         then coalesce(i.due_date,
                       (e.done_on + i.interval_months * interval '1 month')::date)
    end as next_due_on
  from public.maintenance_item i
  -- The newest event is "last done". No event at all is a legitimate state for
  -- the 2034 prop overhaul, which has never been done, hence the left join.
  left join lateral (
    select ev.done_on, ev.tach
    from public.maintenance_event ev
    where ev.item_id = i.id
    order by ev.done_on desc, ev.created_at desc
    limit 1
  ) e on true
  cross join lateral (
    select public.aircraft_tach_estimate(i.aircraft_id) as tach_now
  ) t
  where i.is_active
)
select
  m.*,
  m.next_due_on - public.aircraft_today() as days_remaining,
  case
    when m.basis = 'tach' and m.hours_used is not null then
      greatest(0, least(1, m.hours_used / m.interval_hours))
    -- A recurring calendar item knows both ends of its span, so it has a
    -- fraction. A bare due_date does not, and gets no bar.
    when m.basis = 'calendar' and m.last_done_on is not null
         and m.next_due_on > m.last_done_on then
      greatest(0, least(1, (public.aircraft_today() - m.last_done_on)::numeric
                           / (m.next_due_on - m.last_done_on)))
  end as fraction_used,
  case
    when m.basis = 'tach' then
      case
        -- No reading ever logged, or never marked done: honestly unknown.
        when m.hours_remaining is null                        then 'unknown'
        when m.hours_remaining <= 0                           then 'overdue'
        when m.hours_remaining <= coalesce(m.lead_hours, 0)   then 'due_soon'
        else 'ok'
      end
    else
      case
        when m.next_due_on is null                            then 'unknown'
        when m.next_due_on <= public.aircraft_today()         then 'overdue'
        when m.next_due_on - public.aircraft_today()
               <= coalesce(m.lead_days, 0)                    then 'due_soon'
        else 'ok'
      end
  end as state
from measured m;

-- ---------------------------------------------------------------------------
-- Row level security
--
-- Snags, readings and done-logs are things any pilot records: a co-owner who
-- finds an oil seep must be able to report it, and one who greases the hub must
-- be able to say so. The ITEMS are shared configuration -- intervals and life
-- limits come off an airworthiness document, not off this screen -- so those
-- are admin-only to write, matching public.aircraft.
-- ---------------------------------------------------------------------------

alter table public.snag              enable row level security;
alter table public.tach_reading      enable row level security;
alter table public.maintenance_item  enable row level security;
alter table public.maintenance_event enable row level security;

revoke all on public.snag               from anon;
revoke all on public.tach_reading       from anon;
revoke all on public.maintenance_item   from anon;
revoke all on public.maintenance_event  from anon;
revoke all on public.maintenance_status from anon;

create policy snag_select_members on public.snag
  for select to authenticated using (public.current_member_id() is not null);
-- Reported by you, or by an admin on someone's behalf.
create policy snag_insert_members on public.snag
  for insert to authenticated
  with check (reported_by = public.current_member_id() or public.is_admin());
-- Any member may clear or re-grade a snag. The owner who fixed the brake is
-- usually not the owner who reported it.
create policy snag_update_members on public.snag
  for update to authenticated
  using (public.current_member_id() is not null)
  with check (public.current_member_id() is not null);
-- Deleting is for a snag entered by mistake, so it stays with its author.
create policy snag_delete_own on public.snag
  for delete to authenticated using (reported_by = public.current_member_id());
create policy snag_admin_all on public.snag
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy tach_reading_select_members on public.tach_reading
  for select to authenticated using (public.current_member_id() is not null);
-- read_by is not forced to the caller: the trigger above attributes a
-- flight-derived reading to the flight's pilot, which an admin logging a flight
-- for someone else would otherwise be refused.
create policy tach_reading_insert_members on public.tach_reading
  for insert to authenticated
  with check (public.current_member_id() is not null);
create policy tach_reading_write_own on public.tach_reading
  for update to authenticated
  using (read_by = public.current_member_id())
  with check (read_by = public.current_member_id());
create policy tach_reading_delete_own on public.tach_reading
  for delete to authenticated using (read_by = public.current_member_id());
create policy tach_reading_admin_all on public.tach_reading
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy maintenance_item_select_members on public.maintenance_item
  for select to authenticated using (public.current_member_id() is not null);
create policy maintenance_item_admin_write on public.maintenance_item
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy maintenance_event_select_members on public.maintenance_event
  for select to authenticated using (public.current_member_id() is not null);
create policy maintenance_event_insert_members on public.maintenance_event
  for insert to authenticated
  with check (done_by = public.current_member_id() or public.is_admin());
create policy maintenance_event_write_own on public.maintenance_event
  for update to authenticated
  using (done_by = public.current_member_id())
  with check (done_by = public.current_member_id());
create policy maintenance_event_delete_own on public.maintenance_event
  for delete to authenticated using (done_by = public.current_member_id());
create policy maintenance_event_admin_all on public.maintenance_event
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

grant select on public.maintenance_status to authenticated;
