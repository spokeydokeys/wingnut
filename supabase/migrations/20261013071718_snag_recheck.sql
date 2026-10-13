-- When should this snag come back to my attention?
--
-- A watch item is not a reminder unless something reminds you. "Oil seep at the
-- valve cover" is worth looking at again, but not today and not on a date --
-- it is worth looking at next time the cowling is off. "Changed oil type,
-- check again in 10 hr" is the same question answered in tach hours.
--
-- So one question, three ways to answer it, at most one at a time:
--
--   recheck_item_id     at the next <maintenance item>
--   recheck_tach_hours  after this many hours on the tach
--   recheck_on          on this date
--
-- The first is the one that earns its keep. Marking the prop hub grease done
-- shows the snags waiting on that job while the cowling is still off, instead
-- of reminding anyone at the kitchen table that evening.
--
-- Deliberately NOT here:
--   - Promoting a snag into a maintenance_item. That table is the airworthiness
--     programme -- intervals come off a document and `maintenance_item_admin_write`
--     keeps pilots out of them -- and it needs an admin editor first. A
--     pilot-authored "check again in 10 hr" is a note about a snag, not a new
--     line in the programme, and this is where it belongs.
--   - Any stored "due" flag. Due-ness is arithmetic on the tach estimate and
--     today's date, both of which move on their own, so it is computed where it
--     is read -- the same reason maintenance_status is a view.

alter table public.snag
  -- set null, not cascade: retiring a maintenance item must not take the snag
  -- that was waiting on it. The snag then reads as having no re-check, which is
  -- true, and is fixable on its own screen.
  add column recheck_item_id uuid references public.maintenance_item(id)
    on delete set null,
  add column recheck_tach_hours numeric(6,1) check (recheck_tach_hours > 0),
  -- The tach the clock started from, stamped by the trigger below rather than
  -- sent by the caller. Nullable because an aeroplane with no reading at all has
  -- no datum to measure from, and "in 10 hr" is still a sensible thing to have
  -- asked for -- the screens say the hours are unmeasurable until a reading
  -- exists rather than refusing the request.
  add column recheck_tach_base numeric(10,2) check (recheck_tach_base >= 0),
  add column recheck_on date,

  -- Three answers to one question, so at most one may be given. Without this a
  -- snag could be due in 10 hr AND at the next oil change AND on Friday, and
  -- every screen would have to invent a precedence rule.
  add constraint snag_recheck_one_way check (
    (recheck_item_id is not null)::int
    + (recheck_tach_hours is not null)::int
    + (recheck_on is not null)::int <= 1
  ),

  -- A datum with nothing measured from it is meaningless. The reverse is
  -- allowed, as above.
  add constraint snag_recheck_base_needs_hours check (
    recheck_tach_base is null or recheck_tach_hours is not null
  );

comment on column public.snag.recheck_tach_base is
  'Tach estimate when the hour-based re-check was set. Stamped by snag_stamp_recheck, never by the caller.';

-- For the mark-done screen's "waiting on this job" query. Partial, because the
-- only rows it ever asks for are live snags pointed at one item.
create index snag_recheck_item_idx on public.snag (recheck_item_id)
  where recheck_item_id is not null and status <> 'cleared';

-- ---------------------------------------------------------------------------
-- Arming the hour-based re-check
--
-- "In 10 hr" has to mean ten hours from when it was asked for, which means
-- remembering the tach at that moment. Two things follow, and both are why this
-- is a trigger rather than a column the form fills in:
--
-- 1. The base is read from the database, like cleared_by above it. A caller
--    that could choose the datum could choose to have been reminded last week.
--
-- 2. The base moves only when the interval does. Re-saving a snag's notes would
--    otherwise re-stamp the base against a tach that has crept forward since,
--    quietly pushing the re-check further away every time anyone looked at it.
-- ---------------------------------------------------------------------------

create function public.snag_stamp_recheck()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- A cleared snag has nothing left to come back to, and the same reasoning as
  -- `grounding`: the re-check described a state the snag is no longer in.
  if new.status = 'cleared' then
    new.recheck_item_id    := null;
    new.recheck_tach_hours := null;
    new.recheck_on         := null;
  end if;

  if new.recheck_tach_hours is null then
    new.recheck_tach_base := null;
  elsif tg_op = 'INSERT'
     or old.recheck_tach_hours is distinct from new.recheck_tach_hours then
    new.recheck_tach_base := public.aircraft_tach_estimate(new.aircraft_id);
  else
    new.recheck_tach_base := old.recheck_tach_base;
  end if;

  return new;
end;
$$;

-- Fires after snag_stamp_cleared, alphabetically, which is the order that
-- matters: that one owns the status's consequences for the clearing stamp and
-- this one owns them for the re-check.
create trigger snag_stamp_recheck
  before insert or update on public.snag
  for each row execute function public.snag_stamp_recheck();
