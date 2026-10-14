-- Aircraft notes: what somebody did to the aeroplane, that nobody has to act on.
--
-- "I added a qt of oil." "I put air in the tires." Asked for by the owner on
-- 14 Oct 2026. None of the three tables that already exist is the right home:
--
--   snag              a defect somebody has to decide about. That list answers
--                     "is it grounded?", and the snag form's one real question
--                     is "when should this come back to my attention?" --
--                     which, for a quart of oil, has no answer.
--
--   maintenance_event resets a SCHEDULED item's counter; item_id is not null
--                     and there is no item for topping up oil. The programme is
--                     airworthiness, and a note is not part of it.
--
--   flight.notes      stays with its flight. "Is the engine using oil?" would
--                     then mean reading every flight's notes one at a time,
--                     which is the question this table exists to make answerable
--                     at a glance.
--
-- So: a running log on the aeroplane, in its own table, deliberately dull.
-- There is no status, no assignee and nothing to clear. A note is a fact about
-- a day, and the only thing anybody does with it is read it.
--
-- Free text plus an optional tach, settled with the owner 14 Oct 2026. A typed
-- "oil added, N quarts" field was offered and declined: it is more form to fill
-- in at the dock every time, and the trend it would buy is not worth that yet.

create table public.aircraft_note (
  id          uuid primary key default gen_random_uuid(),
  aircraft_id uuid not null references public.aircraft(id) on delete cascade,

  body        text not null check (length(trim(body)) > 0),

  -- The day the thing was done, which is not always the day it was written
  -- down. Defaults to today where the aeroplane is -- never current_date, which
  -- is the server's idea of the date and is already tomorrow after 5pm Pacific.
  noted_on    date not null default public.aircraft_today(),

  noted_by    uuid references public.member(id) on delete set null,

  -- What the meter said, if whoever it was looked. Optional on purpose: being
  -- made to walk back to the cockpit for a number is how a note stops being
  -- written at all.
  tach        numeric(10,2) check (tach >= 0),

  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index aircraft_note_recent_idx
  on public.aircraft_note (aircraft_id, noted_on desc, created_at desc);

create trigger aircraft_note_set_updated_at
  before update on public.aircraft_note
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- A note's tach IS a tach reading
--
-- The same argument as flight_sync_tach_reading in 20261013025135: without this
-- the field is a dead end, stored on the note and invisible to maintenance, and
-- whoever typed it would be asked for the same number again under "Log tach
-- reading". One source of truth, written from wherever it was read.
--
-- read_at is NOON on noted_on, matching what the tach screen does with a
-- date-only input. Midnight would sort a note before the morning flight that
-- happened the same day, and aircraft_tach_estimate counts flights that START
-- after the reading -- so a midnight stamp would count that flight on top of a
-- reading taken after it.
-- ---------------------------------------------------------------------------

alter table public.tach_reading
  add column note_id uuid references public.aircraft_note(id) on delete cascade;

-- One reading per note, so re-saving a note updates its reading rather than
-- leaving a trail of them. Same shape as tach_reading_one_per_flight.
create unique index tach_reading_one_per_note
  on public.tach_reading (note_id) where note_id is not null;

-- A reading belongs to at most one of the two things that can produce it.
-- Without this a row could claim to come from a flight and a note at once, and
-- the two syncs would fight over it.
alter table public.tach_reading
  add constraint tach_reading_one_origin
  check (flight_id is null or note_id is null);

create function public.aircraft_note_sync_tach_reading()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.tach is null then
    -- The number was cleared, or was never there. The reading it stood for
    -- does not exist either.
    delete from public.tach_reading where note_id = new.id;
    return null;
  end if;

  insert into public.tach_reading
    (aircraft_id, reading, read_at, read_by, source, note_id)
  values
    (new.aircraft_id, new.tach,
     (new.noted_on + time '12:00') at time zone 'America/Vancouver',
     new.noted_by, 'manual', new.id)
  on conflict (note_id) where note_id is not null do update
    set aircraft_id = excluded.aircraft_id,
        reading     = excluded.reading,
        read_at     = excluded.read_at,
        read_by     = excluded.read_by;

  return null;
end;
$$;

create trigger aircraft_note_sync_tach_reading
  after insert or update of tach, noted_on, aircraft_id, noted_by
  on public.aircraft_note
  for each row execute function public.aircraft_note_sync_tach_reading();

-- ---------------------------------------------------------------------------
-- Who may write one
--
-- Every member reads every note: the log is about the aeroplane, and the
-- aeroplane is shared. Writing is attributed to the caller, and correcting or
-- deleting one stays with whoever wrote it -- a note is somebody's account of
-- what they did, and another owner editing it would make it evidence of
-- nothing. An admin can still do both, as everywhere else.
-- ---------------------------------------------------------------------------

alter table public.aircraft_note enable row level security;

revoke all on public.aircraft_note from anon;

create policy aircraft_note_select_members on public.aircraft_note
  for select to authenticated using (public.current_member_id() is not null);

create policy aircraft_note_insert_own on public.aircraft_note
  for insert to authenticated
  with check (noted_by = public.current_member_id() or public.is_admin());

create policy aircraft_note_write_own on public.aircraft_note
  for update to authenticated
  using (noted_by = public.current_member_id())
  with check (noted_by = public.current_member_id());

create policy aircraft_note_delete_own on public.aircraft_note
  for delete to authenticated
  using (noted_by = public.current_member_id());

create policy aircraft_note_admin_all on public.aircraft_note
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

comment on table public.aircraft_note is
  'A running log of what was done to the aeroplane -- oil added, tyres pumped -- that nobody has to act on. Not a snag (no defect), not a maintenance_event (resets no scheduled item).';

comment on column public.aircraft_note.tach is
  'What the meter said, if it was looked at. Mirrored into tach_reading by aircraft_note_sync_tach_reading, so a note moves the maintenance due-dates.';
