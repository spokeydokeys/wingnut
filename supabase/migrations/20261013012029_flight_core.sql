-- Flights: the timer, the log, and the hand-editing the spec insists on.
--
-- Three ideas carry this migration.
--
-- 1. A flight's hours are DERIVED from start_at and end_at, never typed in.
--    SPEC.md 4.1 makes hand-editing a requirement ("people forget to stop the
--    clock"), so the editable truth is the two timestamps and everything else
--    follows. flight_hours is a generated column and cannot drift; billed and
--    estimated tach hours are set by a trigger, because they depend on the
--    aircraft's settings and a generated column may not read another table.
--
-- 2. The tach factor is SNAPSHOT onto each flight. SPEC.md 4.4 says the app
--    should compute the real flight-time-to-tach ratio from actual readings and
--    suggest updating the factor, so the factor WILL change. Without a snapshot,
--    changing it would silently restate the engine hours of every past flight.
--
-- 3. The raw GPS fixes live in their own table, not in columns on flight.
--    SPEC.md 4.2: "if Stop was pressed at home, the raw fix is a home location
--    ... discard or hide the raw end fix from the co-owner's view." That is a
--    row-level rule, and RLS cannot restrict columns, so the fixes have to be
--    rows to be protected. Co-owners see the corrected place; only the pilot
--    (and an admin) sees the coordinates.
--
-- Billed hours are NOT snapshot from a rate: the effective-dated rate schedules
-- from the ledger migration already resolve a past flight at the rate in force
-- on its date, which is what SPEC.md 4.6 asks for.

create type public.flight_status as enum ('draft', 'confirmed', 'billed');
create type public.fix_source   as enum ('gps', 'manual');
create type public.fix_which    as enum ('start', 'end');

create type public.place_kind as enum
  ('airport', 'water_aerodrome', 'heliport', 'bay', 'lake', 'dock', 'other');

-- Where the place came from. Imported rows are shared reference data; 'saved'
-- rows are the user's own docks and moorings, which they may edit.
create type public.place_source as enum
  ('ourairports', 'osm', 'bcgnis', 'saved');

-- ---------------------------------------------------------------------------
-- Places
--
-- Minimal on purpose. Ranked nearby matching and the OurAirports/OSM import
-- are a later phase; this is the table a flight's origin and destination point
-- at, plus the saved docks and moorings from the More tab.
-- ---------------------------------------------------------------------------

create table public.place (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.company(id) on delete cascade,
  name        text not null,
  kind        public.place_kind not null default 'other',
  source      public.place_source not null default 'saved',
  lat         numeric(9,6) not null check (lat between -90 and 90),
  lon         numeric(9,6) not null check (lon between -180 and 180),
  -- The identifier from the upstream dataset, so a re-import updates rather
  -- than duplicates. Null for user-saved places.
  external_id text,
  created_by  uuid references public.member(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (company_id, source, external_id)
);

create index place_lookup_idx on public.place (company_id, lat, lon);

create trigger place_set_updated_at
  before update on public.place
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Hour rounding
--
-- Billed hours round UP to a tenth (confirmed with the owner). Estimated tach
-- deliberately rounds to NEAREST instead: it is an engine-life estimate, not a
-- charge, and rounding an estimate up every flight would overstate engine hours
-- and retire the engine early. The enum is named billed_hour_rounding for that
-- reason -- it governs the invoice, not the logbook.
--
-- Takes exact hours, so it must be fed the raw interval rather than a value
-- that has already been rounded for display: 0.7049 rounds up to 0.8, but
-- 0.70 rounds up to 0.7.
-- ---------------------------------------------------------------------------

create function public.round_hours(p_hours numeric, p_rule public.hour_rounding)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select case p_rule
    when 'round_up_tenth' then ceil(p_hours * 10) / 10
    when 'nearest_tenth'  then round(p_hours * 10) / 10
    when 'exact'          then p_hours
  end;
$$;

comment on function public.round_hours is
  'Rounds exact hours by an aircraft rounding rule. Numeric throughout, so 0.8 hr stays 0.8 rather than creeping up through binary float error.';

-- ---------------------------------------------------------------------------
-- Flights
-- ---------------------------------------------------------------------------

create table public.flight (
  id               uuid primary key default gen_random_uuid(),
  aircraft_id      uuid not null references public.aircraft(id) on delete restrict,
  pilot_member_id  uuid not null references public.member(id) on delete restrict,
  status           public.flight_status not null default 'draft',

  -- The editable truth. end_at is null exactly while the timer is running.
  --
  -- start_at defaults to now() so that pressing Start reads the database's
  -- clock rather than a web server's or a phone's. A flight logged after the
  -- fact passes its own value, and the default stays out of the way.
  start_at         timestamptz not null default now(),
  end_at           timestamptz,

  -- Snapshot of aircraft.tach_factor when the flight was logged, so later
  -- tuning of the factor cannot restate past engine hours.
  tach_factor_used numeric(5,3) not null check (tach_factor_used > 0),

  -- Exact wall-clock duration, for the "0:48 flight time" caption. Generated,
  -- so it can never disagree with the timestamps above.
  flight_hours     numeric(6,2)
    generated always as (
      round(extract(epoch from (end_at - start_at)) / 3600, 2)
    ) stored,

  -- Set by trigger from the exact interval: billed rounds up, tach is nearest.
  billed_hours     numeric(6,2),
  est_tach_hours   numeric(6,2),

  -- What the pilot actually read off the tach, if they looked. Feeds the
  -- factor-correction suggestion and the maintenance counters.
  actual_tach_hours numeric(10,2) check (actual_tach_hours >= 0),

  origin_place_id  uuid references public.place(id) on delete set null,
  dest_place_id    uuid references public.place(id) on delete set null,

  -- Non-identifying fix metadata. The coordinates themselves are in
  -- flight_fix, which is restricted to the pilot.
  start_fix_at          timestamptz,
  start_fix_accuracy_m  numeric(7,1) check (start_fix_accuracy_m >= 0),
  end_fix_at            timestamptz,
  end_fix_accuracy_m    numeric(7,1) check (end_fix_accuracy_m >= 0),

  -- SPEC.md 4.2 forgot-to-end case: the stop fix matched nothing known, so the
  -- Confirm screen warns and asks for the real landing place and end time.
  landing_place_uncertain boolean not null default false,

  journey_text     text,
  notes            text,

  -- Set when a month is closed. A flight on an issued invoice is frozen.
  invoice_id       uuid references public.invoice(id) on delete restrict,

  -- Shortcut/API retries must not create a second flight. Null for flights
  -- started in the app.
  start_idempotency_key text,
  stop_idempotency_key  text,

  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  constraint flight_ends_after_start
    check (end_at is null or end_at > start_at),
  -- Only a draft may still be running; confirming a flight requires an end.
  constraint flight_finished_unless_draft
    check (status = 'draft' or end_at is not null),
  -- A flight is only on an invoice once it has been billed.
  constraint flight_invoiced_only_when_billed
    check ((status = 'billed') = (invoice_id is not null))
);

create index flight_log_idx on public.flight (aircraft_id, start_at desc);
create index flight_pilot_idx on public.flight (pilot_member_id, start_at desc);
create index flight_invoice_idx on public.flight (invoice_id);

-- Two pilots cannot both have the clock running on the same aeroplane, and a
-- double-tapped Start cannot open a second flight. Enforced by the database
-- because the Shortcut can fire twice on a flaky connection.
create unique index flight_one_open_per_aircraft
  on public.flight (aircraft_id) where end_at is null;

-- Idempotency keys are only unique where present.
create unique index flight_start_idempotency_key_idx
  on public.flight (start_idempotency_key) where start_idempotency_key is not null;
create unique index flight_stop_idempotency_key_idx
  on public.flight (stop_idempotency_key) where stop_idempotency_key is not null;

create trigger flight_set_updated_at
  before update on public.flight
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Derived hours
--
-- Recomputed on every write so a hand-edited end time immediately reprices the
-- flight. A running flight has no hours yet.
-- ---------------------------------------------------------------------------

create function public.flight_compute_hours()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_exact_hours numeric;
  v_rounding    public.hour_rounding;
  v_factor      numeric;
begin
  select a.billed_hour_rounding, a.tach_factor into v_rounding, v_factor
  from public.aircraft a where a.id = new.aircraft_id;

  -- Default the snapshot from the aircraft so a caller cannot forget it, but
  -- never overwrite one that is already set: a flight logged weeks late keeps
  -- the factor it was logged with. A BEFORE trigger can populate a NOT NULL
  -- column, because constraints are checked after triggers have run.
  new.tach_factor_used := coalesce(new.tach_factor_used, v_factor);

  if new.end_at is null then
    new.billed_hours   := null;
    new.est_tach_hours := null;
    return new;
  end if;

  -- The exact interval, not new.flight_hours: that column is rounded to two
  -- decimals for display, and rounding twice changes the answer.
  v_exact_hours := extract(epoch from (new.end_at - new.start_at)) / 3600;

  new.billed_hours   := public.round_hours(v_exact_hours, v_rounding);
  new.est_tach_hours := public.round_hours(
                          v_exact_hours / new.tach_factor_used, 'nearest_tenth');
  return new;
end;
$$;

create trigger flight_compute_hours
  before insert or update on public.flight
  for each row execute function public.flight_compute_hours();

-- ---------------------------------------------------------------------------
-- Locking
--
-- SPEC.md 4.1: "Every field on a flight can be corrected until the month is
-- closed." 4.6: closing a month locks that month's flights, and later edits
-- become adjustment lines on the next bill. So the cutoff is exactly billing.
-- ---------------------------------------------------------------------------

create function public.guard_flight_locked()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.status = 'billed' then
      raise exception
        'flight % has been billed and cannot be deleted; raise an adjustment instead',
        old.id;
    end if;
    return old;
  end if;

  if old.status <> 'billed' then
    return new;
  end if;

  -- Past billing only the sync fields and the notes may move. Hours, times,
  -- pilot and places are what the invoice was computed from.
  if (new.aircraft_id, new.pilot_member_id, new.start_at, new.end_at,
      new.tach_factor_used, new.billed_hours, new.est_tach_hours,
      new.origin_place_id, new.dest_place_id, new.invoice_id, new.status)
     is distinct from
     (old.aircraft_id, old.pilot_member_id, old.start_at, old.end_at,
      old.tach_factor_used, old.billed_hours, old.est_tach_hours,
      old.origin_place_id, old.dest_place_id, old.invoice_id, old.status)
  then
    raise exception
      'flight % has been billed and cannot be edited; raise an adjustment instead',
      old.id;
  end if;

  return new;
end;
$$;

create trigger flight_guard_locked
  before update or delete on public.flight
  for each row execute function public.guard_flight_locked();

-- ---------------------------------------------------------------------------
-- GPS fixes
--
-- Separate table, and private to the pilot, because a fix taken at Stop can be
-- a home address. The co-owner sees the corrected place on the flight row and
-- never the coordinates. "Discard the raw fix" is a DELETE here, which is why
-- the flight row keeps its own place and accuracy columns -- deleting a fix
-- must not erase the flight's history.
-- ---------------------------------------------------------------------------

create table public.flight_fix (
  flight_id   uuid not null references public.flight(id) on delete cascade,
  which       public.fix_which not null,
  lat         numeric(9,6) not null check (lat between -90 and 90),
  lon         numeric(9,6) not null check (lon between -180 and 180),
  accuracy_m  numeric(7,1) check (accuracy_m >= 0),
  -- When the phone took the fix, which is not quite created_at: a fix can be
  -- written a moment after it was read, and on a slow connection rather more
  -- than a moment. Defaults to now() because the usual case is "just now".
  taken_at    timestamptz not null default now(),
  source      public.fix_source not null default 'gps',
  created_at  timestamptz not null default now(),
  primary key (flight_id, which)
);

-- ---------------------------------------------------------------------------
-- Shortcut API tokens
--
-- SPEC.md 7: the timer endpoints are token-authenticated so an iOS Shortcut can
-- start and stop a flight without a browser session.
--
-- Its own table rather than a column on member, for the same reason the GPS
-- fixes are: member_select_members lets every co-owner read every column of
-- every member row, and RLS cannot restrict columns. A token hash is not a
-- token, but it is still a credential digest and there is no reason for a
-- co-owner to hold it. As rows it is protected by the mechanism that actually
-- does per-row restriction.
--
-- Only the hash is ever stored. The token is generated in the app with a CSPRNG
-- and shown once; a database leak therefore hands over no working tokens.
-- ---------------------------------------------------------------------------

create table public.api_token (
  id           uuid primary key default gen_random_uuid(),
  member_id    uuid not null references public.member(id) on delete cascade,
  token_hash   text not null unique,
  label        text,
  created_at   timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at   timestamptz
);

create index api_token_member_idx on public.api_token (member_id);

-- ---------------------------------------------------------------------------
-- The timer API (SPEC.md 7)
--
-- The whole operation is one security-definer function rather than a set of
-- table grants, because the caller has no session: an iOS Shortcut presents a
-- bearer token and nothing else. Doing it this way means the API surface for an
-- unauthenticated caller is exactly "start a flight" and "stop a flight", and
-- never "read the member table". The alternative -- handing the route handler a
-- service-role key -- would bypass every policy in the database to save a
-- function.
--
-- The route handler hashes the token before calling, so the raw token never
-- reaches the database or its logs.
--
-- Note these take p_token_hash and derive the member from it. Nothing is taken
-- on trust from the caller about who they are.
-- ---------------------------------------------------------------------------

create function public.member_for_token_hash(p_token_hash text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member uuid;
begin
  if p_token_hash is null or length(p_token_hash) < 32 then
    raise exception 'invalid api token' using errcode = '28000';
  end if;

  select t.member_id into v_member
  from public.api_token t
  join public.member m on m.id = t.member_id
  where t.token_hash = p_token_hash
    and t.revoked_at is null
    and m.is_active;

  if v_member is null then
    raise exception 'invalid api token' using errcode = '28000';
  end if;

  update public.api_token set last_used_at = now() where token_hash = p_token_hash;
  return v_member;
end;
$$;

create function public.timer_start(
  p_token_hash      text,
  p_lat             numeric default null,
  p_lon             numeric default null,
  p_accuracy_m      numeric default null,
  p_idempotency_key text default null,
  p_aircraft_id     uuid    default null
)
returns public.flight
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member   uuid;
  v_aircraft uuid;
  v_flight   public.flight;
  v_open     public.flight;
begin
  v_member := public.member_for_token_hash(p_token_hash);

  -- A retry of the same request must return the same flight, not open a
  -- second one. This is checked before anything else is written.
  if p_idempotency_key is not null then
    select * into v_flight from public.flight
    where start_idempotency_key = p_idempotency_key;
    if v_flight.id is not null then
      return v_flight;
    end if;
  end if;

  v_aircraft := coalesce(p_aircraft_id, (select a.id from public.aircraft a
                                          order by a.created_at limit 1));
  if v_aircraft is null then
    raise exception 'no aircraft to fly';
  end if;

  -- The partial unique index would catch this, but a bare duplicate-key error
  -- tells the pilot nothing. Their own running flight is returned as-is, which
  -- makes a double-tapped Start harmless even with no idempotency key.
  select * into v_open from public.flight
  where aircraft_id = v_aircraft and end_at is null;

  if v_open.id is not null then
    if v_open.pilot_member_id = v_member then
      return v_open;
    end if;
    raise exception 'the timer is already running for %',
      (select m.full_name from public.member m where m.id = v_open.pilot_member_id)
      using errcode = '55006';
  end if;

  insert into public.flight
    (aircraft_id, pilot_member_id, start_at,
     start_fix_at, start_fix_accuracy_m, start_idempotency_key)
  values
    (v_aircraft, v_member, now(),
     case when p_lat is not null then now() end, p_accuracy_m, p_idempotency_key)
  returning * into v_flight;

  if p_lat is not null and p_lon is not null then
    insert into public.flight_fix (flight_id, which, lat, lon, accuracy_m, taken_at)
    values (v_flight.id, 'start', p_lat, p_lon, p_accuracy_m, now());
  end if;

  return v_flight;
end;
$$;

create function public.timer_stop(
  p_token_hash      text,
  p_lat             numeric default null,
  p_lon             numeric default null,
  p_accuracy_m      numeric default null,
  p_idempotency_key text default null,
  p_aircraft_id     uuid    default null
)
returns public.flight
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member   uuid;
  v_aircraft uuid;
  v_flight   public.flight;
begin
  v_member := public.member_for_token_hash(p_token_hash);

  if p_idempotency_key is not null then
    select * into v_flight from public.flight
    where stop_idempotency_key = p_idempotency_key;
    if v_flight.id is not null then
      return v_flight;
    end if;
  end if;

  v_aircraft := coalesce(p_aircraft_id, (select a.id from public.aircraft a
                                          order by a.created_at limit 1));

  select * into v_flight from public.flight
  where aircraft_id = v_aircraft and end_at is null;

  if v_flight.id is null then
    raise exception 'the timer is not running' using errcode = '55006';
  end if;
  if v_flight.pilot_member_id <> v_member then
    raise exception 'the running flight belongs to another pilot'
      using errcode = '42501';
  end if;

  -- Stays a draft: SPEC.md 4.1 has Stop open the Confirm screen, and the flight
  -- is only confirmed once a human has looked at it.
  update public.flight
     set end_at             = now(),
         end_fix_at         = case when p_lat is not null then now() end,
         end_fix_accuracy_m = p_accuracy_m,
         stop_idempotency_key = p_idempotency_key
   where id = v_flight.id
  returning * into v_flight;

  if p_lat is not null and p_lon is not null then
    insert into public.flight_fix (flight_id, which, lat, lon, accuracy_m, taken_at)
    values (v_flight.id, 'end', p_lat, p_lon, p_accuracy_m, now())
    on conflict (flight_id, which) do update
      set lat = excluded.lat, lon = excluded.lon,
          accuracy_m = excluded.accuracy_m, taken_at = excluded.taken_at;
  end if;

  return v_flight;
end;
$$;

-- These authenticate by token, so they are reachable without a session. That
-- is the point; it is also why they must be the only thing anon can reach.
revoke all on function public.member_for_token_hash(text) from public;
revoke all on function public.timer_start(text, numeric, numeric, numeric, text, uuid) from public;
revoke all on function public.timer_stop(text, numeric, numeric, numeric, text, uuid) from public;
grant execute on function public.timer_start(text, numeric, numeric, numeric, text, uuid)
  to anon, authenticated;
grant execute on function public.timer_stop(text, numeric, numeric, numeric, text, uuid)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- The running flight
--
-- One row at most per aircraft, by the partial unique index above. Used by the
-- home screen to decide between "Start flight" and the running timer.
-- ---------------------------------------------------------------------------

create view public.flight_running
with (security_invoker = on) as
  select f.*
  from public.flight f
  where f.end_at is null;

-- ---------------------------------------------------------------------------
-- Row level security
--
-- Flights are shared: the flight log, who flew when, and the hours behind a
-- bill are all visible to every owner. What is NOT shared is the raw GPS fix.
-- ---------------------------------------------------------------------------

alter table public.place      enable row level security;
alter table public.flight     enable row level security;
alter table public.flight_fix enable row level security;
alter table public.api_token  enable row level security;

revoke all on public.place          from anon;
revoke all on public.flight         from anon;
revoke all on public.flight_fix     from anon;
revoke all on public.api_token      from anon;
revoke all on public.flight_running from anon;

-- Your own tokens and nobody else's -- deliberately including admins, who have
-- no reason to hold another owner's credential digest.
create policy api_token_own on public.api_token
  for all to authenticated
  using (member_id = public.current_member_id())
  with check (member_id = public.current_member_id());

create policy place_select_members on public.place
  for select to authenticated using (public.current_member_id() is not null);
-- Any owner may save a dock or mooring (More tab) and fix up their own.
create policy place_insert_members on public.place
  for insert to authenticated
  with check (public.current_member_id() is not null and source = 'saved');
create policy place_update_own_saved on public.place
  for update to authenticated
  using (source = 'saved' and created_by = public.current_member_id())
  with check (source = 'saved');
create policy place_admin_all on public.place
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy flight_select_members on public.flight
  for select to authenticated using (public.current_member_id() is not null);
-- A pilot logs their own flights. Only an admin may log one against someone
-- else, which is also what lets an admin correct a mis-attributed flight.
create policy flight_insert_own on public.flight
  for insert to authenticated
  with check (pilot_member_id = public.current_member_id());
create policy flight_update_own on public.flight
  for update to authenticated
  using (pilot_member_id = public.current_member_id())
  with check (pilot_member_id = public.current_member_id());
create policy flight_delete_own on public.flight
  for delete to authenticated
  using (pilot_member_id = public.current_member_id());
create policy flight_admin_all on public.flight
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- The privacy rule, as rows: a fix is visible only to the pilot who made it.
create policy flight_fix_own on public.flight_fix
  for all to authenticated
  using (exists (
    select 1 from public.flight f
    where f.id = flight_id and f.pilot_member_id = public.current_member_id()
  ))
  with check (exists (
    select 1 from public.flight f
    where f.id = flight_id and f.pilot_member_id = public.current_member_id()
  ));
create policy flight_fix_admin_all on public.flight_fix
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

grant select on public.flight_running to authenticated;
