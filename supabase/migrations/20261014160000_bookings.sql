-- Bookings: who has the aeroplane, and when.
--
-- SPEC.md 4.5 asks for "a calendar with conflict prevention (no double-booking),
-- and the other pilot's bookings visible". Both halves matter and only one of
-- them is a screen.
--
-- A booking is an INTENTION. It is deliberately not connected to `flight`,
-- which is a record of what happened. Settled with the owner 14 Oct 2026: a
-- link would immediately raise questions the aeroplane does not care about --
-- what to do about a booking nobody flew, a flight nobody booked, a start
-- twenty minutes late -- and none of those has a right answer that is worth
-- enforcing on two people who talk to each other anyway.
--
-- There is no cancelled status either. A booking somebody gave up is not a
-- fact about the aeroplane; it is the absence of one, and keeping tombstones
-- would mean every read and the overlap rule both had to filter them out.

create table public.booking (
  id              uuid primary key default gen_random_uuid(),
  aircraft_id     uuid not null references public.aircraft(id) on delete cascade,

  -- Not nullable: a booking is somebody holding the aeroplane. A row with
  -- nobody on it would block the slot and leave no one to ask about it.
  pilot_member_id uuid not null references public.member(id) on delete cascade,

  start_at        timestamptz not null,
  end_at          timestamptz not null,

  -- "Fuel stop at Ganges, back for dinner." Why the slot is held, for the
  -- other owner deciding whether to ask for it.
  note            text,

  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint booking_ends_after_start check (end_at > start_at)
);

-- ---------------------------------------------------------------------------
-- No double-booking, enforced by the database
--
-- An exclusion constraint rather than a check in the application, because the
-- check cannot be made correct: two owners tapping Book at the same moment
-- both read a free calendar, both pass, and both insert. The gap is small and
-- the consequence is two people at the dock, which is exactly the thing this
-- feature exists to prevent.
--
-- `with =` on aircraft_id needs btree_gist, which is why the extension is
-- created here and not left implicit. A second aeroplane must not block the
-- first one's slots.
--
-- Ranges are [) -- half open. A booking ending at 12:00 and the next starting
-- at 12:00 do not overlap, which is how handing over at noon reads to a person
-- and would not be true of a closed range.
-- ---------------------------------------------------------------------------

create extension if not exists btree_gist with schema public;

alter table public.booking
  add constraint booking_no_overlap
  exclude using gist (
    aircraft_id with =,
    tstzrange(start_at, end_at, '[)') with &&
  );

-- The calendar reads forwards from a day, for every pilot at once.
create index booking_when_idx on public.booking (aircraft_id, start_at);

create trigger booking_set_updated_at
  before update on public.booking
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Who may write one
--
-- Everyone sees everyone's, which SPEC 4.5 asks for by name: a calendar that
-- hid the other owner's bookings could not answer the only question anybody
-- opens it with. Booking and giving up a slot stay with the pilot holding it,
-- so one owner cannot quietly take another's Saturday. An admin can still do
-- both, as everywhere else in this schema.
-- ---------------------------------------------------------------------------

alter table public.booking enable row level security;

revoke all on public.booking from anon;

create policy booking_select_members on public.booking
  for select to authenticated using (public.current_member_id() is not null);

create policy booking_insert_own on public.booking
  for insert to authenticated
  with check (pilot_member_id = public.current_member_id() or public.is_admin());

create policy booking_write_own on public.booking
  for update to authenticated
  using (pilot_member_id = public.current_member_id())
  with check (pilot_member_id = public.current_member_id());

create policy booking_delete_own on public.booking
  for delete to authenticated
  using (pilot_member_id = public.current_member_id());

create policy booking_admin_all on public.booking
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

comment on table public.booking is
  'Who holds the aeroplane and when. An intention, deliberately unlinked to flight (what happened). Overlap is impossible: see booking_no_overlap.';

comment on constraint booking_no_overlap on public.booking is
  'No double-booking, per SPEC 4.5. Half-open ranges, so end 12:00 and start 12:00 are not a clash.';
