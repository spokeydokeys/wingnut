-- Places and the journey log (SPEC.md 4.2).
--
-- Four decisions carry this migration.
--
-- 1. NO PostGIS. The obvious tool for "nearest place within a kilometre" is
--    geography(Point) and ST_DWithin, and Supabase will happily enable the
--    extension. But scripts/verify-restore.sh proves the export restores onto a
--    stock postgres:17 image, and a stock image has no PostGIS -- the restore
--    would fail on the first CREATE EXTENSION. The escape hatch is worth more
--    than an index here: this is one aeroplane and a handful of places, so a
--    haversine over a sequential scan is nothing, and it is pure SQL that
--    restores anywhere.
--
-- 2. GPS fixes are private, full stop. flight_fix_admin_all is dropped below.
--    SPEC.md 4.2 promises the co-owner sees only the corrected place, and both
--    owners here are admins, so the admin policy was quietly cancelling the
--    promise. A raw coordinate is personal rather than financial -- the hours,
--    the place and the journey text stay shared, and those are what a bill or a
--    disagreement is actually settled on.
--
-- 3. The flag is raised by the fix and cleared by the human. A stop fix that
--    matches nothing known sets landing_place_uncertain; naming a landing place
--    clears it, wherever that naming came from. Neither half trusts the app to
--    remember, because the Shortcut API writes fixes too.
--
-- 4. journey_text is DERIVED while it is untouched and typed thereafter. It is
--    built only when both ends are known: half a journey ("Victoria Harbour →")
--    stored as data would be a sentence nobody wrote. The Confirm screen shows
--    the partial form live instead, which costs nothing and persists nothing.

-- How near is "here"? Already answered: aircraft.place_match_radius_m exists
-- from the first migration and defaults to 1 km. Nothing is added for it here,
-- because a second column of the same name on company would be two settings
-- where only one is read.

-- ---------------------------------------------------------------------------
-- Fix privacy
--
-- The remaining policy is flight_fix_own, so a fix is readable by exactly the
-- pilot who recorded it. Dropping the admin policy is deliberately not paired
-- with deleting anything: the owner chose to hide rather than discard, so a fix
-- wrongly matched can still be re-matched by the pilot who holds it.
-- ---------------------------------------------------------------------------

drop policy flight_fix_admin_all on public.flight_fix;

comment on table public.flight_fix is
  'Raw GPS fixes, readable only by the pilot who recorded them -- not by an admin, because every co-owner here is one and SPEC.md 4.2 promises a co-owner sees the corrected place rather than the coordinates. Stop is often pressed at home.';

-- ---------------------------------------------------------------------------
-- Distance
-- ---------------------------------------------------------------------------

create function public.distance_m(
  p_lat1 numeric, p_lon1 numeric,
  p_lat2 numeric, p_lon2 numeric
)
returns numeric
language sql
immutable
parallel safe
set search_path = ''
as $$
  -- Haversine on a sphere of the IUGG mean radius. Good to about 0.3% against
  -- the ellipsoid, which at a 1 km match radius is three metres -- far inside
  -- the accuracy of the phone fix being matched.
  select round((
    2 * 6371008.8 * asin(sqrt(
      power(sin(radians((p_lat2 - p_lat1)::double precision) / 2), 2)
      + cos(radians(p_lat1::double precision))
      * cos(radians(p_lat2::double precision))
      * power(sin(radians((p_lon2 - p_lon1)::double precision) / 2), 2)
    ))
  )::numeric, 1);
$$;

comment on function public.distance_m is
  'Great-circle metres between two lat/lon pairs. Plain SQL rather than PostGIS so that the export restores onto a stock PostgreSQL image.';

-- ---------------------------------------------------------------------------
-- Candidates
--
-- None of these are security definer, so RLS decides which places and flights
-- they can see. place_select_members shares the place list; the usage counts
-- below are the CALLER's own, which is what SPEC.md 4.2 means by "ranked by how
-- often the user has used them" -- the co-owner's habits are not a useful
-- ranking of where this pilot keeps landing.
-- ---------------------------------------------------------------------------

create function public.place_times_used(p_place_id uuid)
returns bigint
language sql
stable
set search_path = ''
as $$
  select count(*)
  from public.flight f
  where f.pilot_member_id = public.current_member_id()
    and p_place_id in (f.origin_place_id, f.dest_place_id);
$$;

create function public.places_near(
  p_lat numeric,
  p_lon numeric,
  p_limit integer default 6
)
returns table (
  id          uuid,
  name        text,
  kind        public.place_kind,
  source      public.place_source,
  lat         numeric,
  lon         numeric,
  distance_m  numeric,
  times_used  bigint
)
language sql
stable
set search_path = ''
as $$
  select p.id, p.name, p.kind, p.source, p.lat, p.lon,
         public.distance_m(p_lat, p_lon, p.lat, p.lon),
         public.place_times_used(p.id)
  from public.place p
  order by public.distance_m(p_lat, p_lon, p.lat, p.lon),
           public.place_times_used(p.id) desc,
           p.name
  limit greatest(p_limit, 0);
$$;

comment on function public.places_near is
  'Nearest places to a fix, nearest first, ties broken by how often the caller has used them. Returns every place rather than only those inside the match radius: the picker shows distances and lets a human decide, and "2.3 km away" is information, not a wrong answer.';

create function public.places_used(p_limit integer default 6)
returns table (
  id           uuid,
  name         text,
  kind         public.place_kind,
  source       public.place_source,
  lat          numeric,
  lon          numeric,
  times_used   bigint,
  last_used_at timestamptz
)
language sql
stable
set search_path = ''
as $$
  with mine as (
    select f.origin_place_id as place_id, f.start_at as used_at
    from public.flight f
    where f.pilot_member_id = public.current_member_id()
      and f.origin_place_id is not null
    union all
    select f.dest_place_id, f.start_at
    from public.flight f
    where f.pilot_member_id = public.current_member_id()
      and f.dest_place_id is not null
  )
  select p.id, p.name, p.kind, p.source, p.lat, p.lon,
         count(*), max(m.used_at)
  from mine m
  join public.place p on p.id = m.place_id
  group by p.id, p.name, p.kind, p.source, p.lat, p.lon
  order by count(*) desc, max(m.used_at) desc
  limit greatest(p_limit, 0);
$$;

comment on function public.places_used is
  'The caller''s own places, most-used first. This is the wireframe''s "Recent" list, which is really a most-used list: the dock you tie up at every week should not fall off it because you flew somewhere else on Sunday.';

create function public.place_match(
  p_aircraft_id uuid,
  p_lat numeric,
  p_lon numeric
)
returns uuid
language sql
stable
set search_path = ''
as $$
  select p.id
  from public.place p
  join public.aircraft a on a.company_id = p.company_id
  where a.id = p_aircraft_id
    and public.distance_m(p_lat, p_lon, p.lat, p.lon) <= a.place_match_radius_m
  order by public.distance_m(p_lat, p_lon, p.lat, p.lon)
  limit 1;
$$;

comment on function public.place_match is
  'The one place a fix is close enough to BE, or null. Unlike places_near this applies the radius, because its answer is written to a flight without anyone looking at it.';

-- ---------------------------------------------------------------------------
-- The journey log entry
-- ---------------------------------------------------------------------------

create function public.journey_sentence(
  p_origin_name text,
  p_dest_name text,
  p_same_place boolean
)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  -- Taking off and landing in the same place is most of what a float plane on
  -- floats does, and "Victoria Harbour → Victoria Harbour" reads as a mistake
  -- rather than as a circuit.
  select case when p_same_place then p_origin_name || ' → local'
              else p_origin_name || ' → ' || p_dest_name end;
$$;

comment on function public.journey_sentence is
  'The wording, given names rather than ids. Split out from journey_text_for because place_refresh_journeys has to reconstruct the sentence an OLD name produced, which cannot be done from ids once the rename has landed.';

create function public.journey_text_for(p_origin_id uuid, p_dest_id uuid)
returns text
language sql
stable
set search_path = ''
as $$
  select public.journey_sentence(o.name, d.name, o.id = d.id)
  from public.place o, public.place d
  where o.id = p_origin_id and d.id = p_dest_id;
$$;

comment on function public.journey_text_for is
  'SPEC.md 4.2''s "Origin → Destination", or null when either end is unknown. Returns no row rather than a half sentence; see the header of this migration.';

create function public.flight_set_journey()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_derived text;
begin
  -- Somebody has said where this landed, so the warning has done its job.
  -- Clearing it here rather than in the app covers every writer: the Confirm
  -- screen, the saved-places manager, and the Shortcut API.
  if new.dest_place_id is not null then
    new.landing_place_uncertain := false;
  end if;

  v_derived := public.journey_text_for(new.origin_place_id, new.dest_place_id);

  if tg_op = 'INSERT' then
    -- Only fill a blank. An insert that names its own journey keeps it.
    if nullif(btrim(coalesce(new.journey_text, '')), '') is null then
      new.journey_text := v_derived;
    end if;
    return new;
  end if;

  -- On update, the question is whether the text on the row is the one this
  -- trigger wrote. If it is, the places moving should move it too; if a human
  -- typed something, it is theirs and the places are not allowed to overwrite
  -- it. Blanking the field asks for the derived text back.
  if nullif(btrim(coalesce(new.journey_text, '')), '') is null
     or new.journey_text is not distinct from
        public.journey_text_for(old.origin_place_id, old.dest_place_id)
  then
    new.journey_text := v_derived;
  end if;

  return new;
end;
$$;

create trigger flight_set_journey
  before insert or update on public.flight
  for each row execute function public.flight_set_journey();

-- ---------------------------------------------------------------------------
-- Renaming a place fixes the journey log
--
-- The sentence is stored on the flight, not computed on read -- it has to be,
-- because a pilot may type their own and that has to survive. The cost is that
-- a rename leaves old sentences behind, which is exactly the case the manager
-- exists for: "Dock" turning out to be "Tod Inlet dock" should correct every
-- journey at once, not only the ones flown since.
--
-- Only sentences this code wrote are touched. A journey a pilot typed is
-- theirs, and a rename is not permission to rewrite it.
--
-- security definer because the renamer is one member and the flights are
-- everybody's: under flight_update_own the UPDATE below would quietly match
-- only the renamer's own flights and leave the co-owner's log stale.
-- ---------------------------------------------------------------------------

create function public.place_refresh_journeys()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.name = old.name then
    return new;
  end if;

  update public.flight f
     set journey_text = public.journey_text_for(f.origin_place_id, f.dest_place_id)
    from public.place o, public.place d
   where o.id = f.origin_place_id
     and d.id = f.dest_place_id
     and new.id in (f.origin_place_id, f.dest_place_id)
     -- The sentence the old name produced. This runs AFTER the rename, so the
     -- joined rows already carry the new name and the renamed end has to be
     -- substituted back by hand.
     and f.journey_text is not distinct from public.journey_sentence(
           case when f.origin_place_id = new.id then old.name else o.name end,
           case when f.dest_place_id = new.id then old.name else d.name end,
           f.origin_place_id = f.dest_place_id);

  return new;
end;
$$;

create trigger place_refresh_journeys
  after update of name on public.place
  for each row execute function public.place_refresh_journeys();

-- ---------------------------------------------------------------------------
-- Matching a fix to a place
--
-- An AFTER trigger on the fix rather than logic in the Server Action, because
-- /api/timer/start and /api/timer/stop write fixes too (SPEC.md 7, the iOS
-- Shortcut) and a rule that only fires on one of two writers is not a rule.
-- ---------------------------------------------------------------------------

create function public.flight_fix_match_place()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_flight public.flight;
  v_place  uuid;
begin
  select * into v_flight from public.flight f where f.id = new.flight_id;

  -- A billed flight is frozen (guard_flight_locked), and writing to it here
  -- would turn a late fix into an exception the pilot cannot act on.
  if not found or v_flight.status = 'billed' then
    return null;
  end if;

  v_place := public.place_match(v_flight.aircraft_id, new.lat, new.lon);

  if new.which = 'start' then
    -- Never overwrite a place a human has already named: the fix is evidence
    -- of where the phone was, and the pilot is the authority on where the
    -- aeroplane was.
    if v_place is not null and v_flight.origin_place_id is null then
      update public.flight set origin_place_id = v_place where id = new.flight_id;
    end if;

  elsif v_place is not null then
    if v_flight.dest_place_id is null then
      update public.flight set dest_place_id = v_place where id = new.flight_id;
    end if;

  elsif v_flight.dest_place_id is null then
    -- SPEC.md 4.2's forgot-to-end case. Note this fires just as readily when
    -- there are no saved places at all, which is the honest answer early on:
    -- the app cannot tell "you landed somewhere new" from "you stopped the
    -- clock in your driveway", and the Confirm screen asks rather than asserts.
    update public.flight
       set landing_place_uncertain = true
     where id = new.flight_id;
  end if;

  return null;
end;
$$;

create trigger flight_fix_match_place
  after insert or update on public.flight_fix
  for each row execute function public.flight_fix_match_place();

-- ---------------------------------------------------------------------------
-- Deleting a place
--
-- The foreign keys are ON DELETE SET NULL, which would quietly empty the
-- origin of a flight flown two years ago and leave its journey text pointing
-- at a place that no longer exists. Renaming is almost always what was meant.
-- ---------------------------------------------------------------------------

create function public.guard_place_in_use()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_used bigint;
begin
  select count(*) into v_used
  from public.flight f
  where old.id in (f.origin_place_id, f.dest_place_id);

  if v_used > 0 then
    raise exception
      'place "%" is on % flight(s) and cannot be deleted; rename it instead',
      old.name, v_used;
  end if;

  return old;
end;
$$;

create trigger place_guard_in_use
  before delete on public.place
  for each row execute function public.guard_place_in_use();

-- ---------------------------------------------------------------------------
-- Backfill
--
-- Flights logged before this migration have places only if somebody set them,
-- which nobody could have. Their journey text is therefore null and stays null;
-- there is nothing to derive it from, and inventing one would be a lie in the
-- logbook. The fixes, where they exist, are left unmatched rather than matched
-- retroactively: place_match reads today's places, and a dock saved next month
-- should not silently rewrite where a flight landed last week.
-- ---------------------------------------------------------------------------
