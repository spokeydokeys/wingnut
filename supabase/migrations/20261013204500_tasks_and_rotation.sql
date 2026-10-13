-- Tasks: the admin chores, and whose turn it is.
--
-- Not in SPEC.md. It exists because of a gap the spec left: the bank
-- reconciliation. The app is the AR sub-ledger and the accounting system is the
-- general ledger, and the bank feed hangs off the GL -- so matching coded
-- expenses against what actually cleared the account happens THERE, not here.
-- A tick-list in this app could catch a wrong coding but could never prove
-- completeness, because an uncoded fuel stop leaves no row to tick.
--
-- What this app owes, then, is not the reconciliation but the reminder. And a
-- reminder nobody owns is a reminder nobody does, which is the whole design:
--
-- 1. A task has an ASSIGNEE. One name, not "the admins".
--
-- 2. Recurring tasks ROTATE, and the turn advances from whoever COMPLETED the
--    last one rather than whoever it was assigned to. Covering for someone must
--    not cost them their turn, and handing yours over must not buy you one.
--
-- 3. The rotation is DERIVED from the active roster, not stored as a list. A
--    third owner joins and starts taking turns the moment they are added; one
--    who leaves drops out. A hand-maintained order would be one more thing to
--    forget to update, and the thing it decides is whose evening gets spent.
--
-- 4. The month-end reconcile is spawned by CLOSING THE MONTH, not by a
--    calendar. You cannot reconcile a month that is not closed, and a task
--    nagging while the bills are still drafts is noise. close_month is
--    re-runnable by design, so the spawn has to be idempotent -- hence the
--    unique index on (series_id, period_month) and the not-exists guard.
--
-- Deliberately NOT here:
--   - Notifications of any kind. The task shows up on Home for the person it
--     belongs to; push notifications need a service worker and a decision about
--     who gets woken up, and they are not what makes the chore get done.
--   - A fixed-schedule cron. Nothing in this stack runs on a timer (no Edge
--     Functions, by the portability rule), so a recurring task is spawned by
--     the event that makes it meaningful -- a month closing, or the previous
--     one being finished.

create type public.task_status as enum ('open', 'done', 'cancelled');

-- How the next one arrives. 'month_close' is spawned by close_month for the
-- month just built; 'interval_days' is spawned when the previous one is ticked.
create type public.task_recurrence as enum ('month_close', 'interval_days');

-- ---------------------------------------------------------------------------
-- task_series
--
-- The standing definition of a recurring chore. Shared configuration, like
-- maintenance_item, so admin-only to write.
--
-- Retire a series by clearing is_active rather than deleting it, so the record
-- of who did which month survives.
-- ---------------------------------------------------------------------------

create table public.task_series (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.company(id) on delete cascade,
  title       text not null check (length(trim(title)) > 0),
  detail      text,
  recurrence  public.task_recurrence not null,

  -- Only for 'interval_days'. Days, not months: "every 90 days" is what a
  -- quarterly chore actually means once it has slipped once.
  interval_days int check (interval_days > 0),

  -- Only for 'month_close'. Days after the end of the period to allow before
  -- it counts as overdue -- the statements have to arrive first.
  due_offset_days int not null default 0 check (due_offset_days >= 0),

  -- The bank rec needs the GL, which a non-admin renter has no business in. A
  -- chore like "wash the floats" does not, hence the switch.
  admins_only boolean not null default true,

  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  -- An interval series with no interval has no way to produce its successor,
  -- and an interval on a month-close series would be read by nothing.
  constraint task_series_interval_matches_recurrence check (
    (recurrence = 'interval_days') = (interval_days is not null)
  )
);

create trigger task_series_set_updated_at
  before update on public.task_series
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- task
--
-- One chore. A one-off has series_id null; that is the only difference.
-- ---------------------------------------------------------------------------

create table public.task (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.company(id) on delete cascade,

  -- set null, not cascade: a retired series must not delete the chores it
  -- produced. Such a task reads as a one-off afterwards, which is true.
  series_id   uuid references public.task_series(id) on delete set null,

  -- Which month this instance is FOR, not when it was made. Null for one-offs
  -- and for interval series.
  period_month date,

  title       text not null check (length(trim(title)) > 0),
  detail      text,

  -- Nullable: a rotation with nobody eligible in it (every admin deactivated)
  -- must still produce the task, so that it is visible and can be picked up,
  -- rather than silently not existing.
  assignee_member_id uuid references public.member(id) on delete set null,

  -- Nullable: "ring the hangar owner sometime" is a real task with no date.
  due_date    date,

  status      public.task_status not null default 'open',

  created_by  uuid references public.member(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  completed_by uuid references public.member(id) on delete set null,
  completed_at timestamptz,

  -- Done and the time it was done move together, so a list can trust either.
  constraint task_done_has_timestamp
    check ((status = 'done') = (completed_at is not null)),

  constraint task_period_is_month_start
    check (period_month = date_trunc('month', period_month)::date)
);

-- The reason close_month can be re-run without minting a second reconcile
-- task, including after the first has been done. Partial, because one-offs and
-- interval tasks have nulls here and must not collide with each other.
create unique index task_series_period_idx on public.task (series_id, period_month)
  where series_id is not null and period_month is not null;

-- For the Home card: my open tasks, soonest first.
create index task_open_idx on public.task (assignee_member_id, due_date)
  where status = 'open';

create trigger task_set_updated_at
  before update on public.task
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Whose turn is it
--
-- Note there is no stored "due" or "overdue" flag anywhere here, for the same
-- reason maintenance_status is a view: overdue-ness is arithmetic on today's
-- date, which moves on its own, so it is computed where it is read.
-- ---------------------------------------------------------------------------

/*
 * The rotation for a series: the eligible members, in a stable order.
 *
 * Ordered by name so the sequence does not depend on insertion order or on a
 * stored index that could drift out of step with the roster. The id is the
 * tiebreak, because two owners could share a name.
 *
 * security definer: used by task_next_assignee, which is itself called from
 * triggers on behalf of whoever ticked the box, and must see the whole roster
 * rather than only what that caller can.
 */
create function public.task_rotation(p_series_id uuid)
-- "turn", not "position": POSITION is a reserved word and a column named that
-- cannot be written without quoting it everywhere.
returns table (member_id uuid, turn int)
language sql
stable
security definer
set search_path = ''
as $$
  select m.id, (row_number() over (order by m.full_name, m.id))::int
  from public.task_series s
  join public.member m on m.is_active
    and (not s.admins_only or m.role = 'admin'::public.member_role)
  where s.id = p_series_id;
$$;

/*
 * Who should get the next one.
 *
 * The turn advances from the member who COMPLETED the series' most recent
 * task. Three cases fall back to the top of the rotation, and they are the same
 * case as far as this is concerned: nobody has done one yet, the last person to
 * do one has since left the rotation, or they were last in it.
 */
create function public.task_next_assignee(p_series_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_last uuid;
  v_next uuid;
begin
  select t.completed_by into v_last
  from public.task t
  where t.series_id = p_series_id
    and t.status = 'done'
    and t.completed_by is not null
  order by t.completed_at desc, t.id desc
  limit 1;

  if v_last is not null then
    select r.member_id into v_next
    from public.task_rotation(p_series_id) r
    where r.turn > (
      -- Null when the last completer is no longer eligible, which makes the
      -- comparison null, which selects nobody -- and drops through below.
      select r2.turn
      from public.task_rotation(p_series_id) r2
      where r2.member_id = v_last
    )
    order by r.turn
    limit 1;
  end if;

  if v_next is null then
    select r.member_id into v_next
    from public.task_rotation(p_series_id) r
    order by r.turn
    limit 1;
  end if;

  return v_next;
end;
$$;

-- ---------------------------------------------------------------------------
-- Ticking one off
-- ---------------------------------------------------------------------------

/*
 * Keep the completion fields in step with the status, so no caller has to --
 * which is also what makes the check constraint above satisfiable from a
 * one-field form. Same shape, and the same reasons, as snag_stamp_cleared:
 * stamped from the database on the TRANSITION only, so a crafted request
 * cannot say someone else did the bank rec, and re-saving a done task's notes
 * keeps the original stamp.
 *
 * Un-ticking is therefore just status = 'open', and it forgets who did it, on
 * purpose: that information described a state the task is no longer in.
 */
create function public.task_stamp_completed()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'done' then
    if tg_op = 'INSERT' or old.status is distinct from 'done' then
      new.completed_at := now();
      new.completed_by := public.current_member_id();
    else
      new.completed_at := old.completed_at;
      new.completed_by := old.completed_by;
    end if;
  else
    new.completed_at := null;
    new.completed_by := null;
  end if;
  return new;
end;
$$;

create trigger task_stamp_completed
  before insert or update on public.task
  for each row execute function public.task_stamp_completed();

/*
 * An interval series produces its successor when the current one is ticked.
 *
 * Spawn-on-completion rather than a generated calendar of occurrences: a chore
 * is not a permanent property of the aeroplane the way a maintenance item is,
 * and "every 90 days" that has slipped a fortnight means 90 days from when it
 * was actually done, not from when it was meant to be.
 *
 * The not-exists guard is what makes un-ticking safe: without it, reopening a
 * task and completing it again would mint a second successor.
 *
 * AFTER, so the row it reads its next assignee from is the one just completed.
 */
create function public.task_spawn_successor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status <> 'done' then
    return null;
  end if;
  if tg_op = 'UPDATE' and old.status = 'done' then
    return null;
  end if;

  insert into public.task (
    company_id, series_id, title, detail, assignee_member_id, due_date
  )
  select
    s.company_id, s.id, s.title, s.detail,
    public.task_next_assignee(s.id),
    public.aircraft_today() + s.interval_days
  from public.task_series s
  where s.id = new.series_id
    and s.is_active
    and s.recurrence = 'interval_days'::public.task_recurrence
    and not exists (
      select 1 from public.task t
      where t.series_id = s.id and t.status = 'open'::public.task_status
    );

  return null;
end;
$$;

create trigger task_spawn_successor
  after insert or update on public.task
  for each row execute function public.task_spawn_successor();

-- ---------------------------------------------------------------------------
-- The month-end chores
-- ---------------------------------------------------------------------------

/*
 * Create the month-close chores for a period, if they are not already there.
 *
 * Idempotent, because close_month is re-runnable: an admin who closes the
 * month, spots a flight with the wrong times, fixes it and closes again must
 * not collect a second reconcile task -- nor get a done one resurrected.
 *
 * Returns how many were created, which is 0 on every close after the first.
 */
create function public.task_spawn_for_month(p_company_id uuid, p_month date)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_start date := date_trunc('month', p_month)::date;
  v_made  int;
begin
  insert into public.task (
    company_id, series_id, period_month, title, detail,
    assignee_member_id, due_date
  )
  select
    s.company_id, s.id, v_start,
    s.title || ' — ' || to_char(v_start, 'Mon YYYY'),
    s.detail,
    public.task_next_assignee(s.id),
    -- From the end of the period it is about, plus the grace the series asks
    -- for: the statements have to arrive before anyone can tick this.
    (v_start + interval '1 month - 1 day')::date + s.due_offset_days
  from public.task_series s
  where s.company_id = p_company_id
    and s.is_active
    and s.recurrence = 'month_close'::public.task_recurrence
    and not exists (
      select 1 from public.task t
      where t.series_id = s.id and t.period_month = v_start
    );

  get diagnostics v_made = row_count;
  return v_made;
end;
$$;

/*
 * Replaced to add one line: the month-close chores are spawned by closing the
 * month. Everything else is as it was in 20261013101500.
 *
 * It lives in the database rather than in the server action that calls
 * close_month because the reminder must not depend on which door the close came
 * through -- the same reasoning as flight_set_journey, which the Shortcut API
 * also writes through.
 */
create or replace function public.close_month(p_aircraft_id uuid, p_month date)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company  uuid;
  v_start    date := date_trunc('month', p_month)::date;
  v_member   record;
  v_invoice  uuid;
  v_status   public.invoice_status;
  v_lines    int;
  v_built    int := 0;
begin
  if not public.is_admin() then
    raise exception 'only an admin can close a month';
  end if;

  select a.company_id into v_company
  from public.aircraft a where a.id = p_aircraft_id;
  if v_company is null then
    raise exception 'no such aircraft: %', p_aircraft_id;
  end if;

  if v_start > public.aircraft_today() then
    raise exception 'cannot close %, it has not started yet', to_char(v_start, 'Mon YYYY');
  end if;

  for v_member in
    select m.id from public.member m where m.is_active order by m.full_name
  loop
    select i.id, i.status into v_invoice, v_status
    from public.invoice i
    where i.company_id = v_company
      and i.member_id = v_member.id
      and i.period_month = v_start;

    -- Reset explicitly. A plpgsql variable that a SELECT INTO found no row for
    -- keeps the value it had on the previous turn of this loop, so without
    -- this the second member would inherit the first member's invoice.
    if not found then
      v_invoice := null;
      v_status  := null;
    end if;

    -- An issued invoice is the record of what was sent. Rebuilding it would be
    -- the "sent invoice changes silently" that SPEC.md 4.6 forbids; the fix for
    -- a mistake found afterwards is an adjustment on the next bill.
    if v_status is not null and v_status <> 'draft' then
      continue;
    end if;

    if v_invoice is null then
      insert into public.invoice (company_id, member_id, period_month)
      values (v_company, v_member.id, v_start)
      returning id into v_invoice;
    else
      delete from public.ledger_entry where invoice_id = v_invoice;
    end if;

    insert into public.ledger_entry (
      company_id, member_id, invoice_id, kind, entry_date, description,
      quantity, unit_rate, amount, gst_amount, tax_treatment, gl_account_code
    )
    select
      v_company, v_member.id, v_invoice, c.kind,
      -- Dated the last day of the period, not today: the charge belongs to the
      -- month it was incurred in, whenever the admin got round to closing it.
      (v_start + interval '1 month - 1 day')::date,
      c.description, c.quantity, c.unit_rate, c.amount, c.gst_amount,
      c.tax_treatment, c.gl_account_code
    from public.month_charges(p_aircraft_id, v_member.id, v_start) c;

    get diagnostics v_lines = row_count;

    -- A member who did not fly and owns nothing gets no invoice at all, rather
    -- than a $0.00 one to ignore.
    if v_lines = 0 then
      delete from public.invoice where id = v_invoice;
    else
      v_built := v_built + 1;
    end if;
  end loop;

  -- The month is now built, so the chores that are about a built month exist.
  perform public.task_spawn_for_month(v_company, v_start);

  return v_built;
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS
--
-- A task is shared work. Any member may see every task, pick one up, hand one
-- over or tick one off: the owner who reconciles the month is often not the one
-- it landed on, and gating "who may tick the box" would buy nothing but
-- friction. Who actually did it is recorded by the stamp trigger, not by the
-- policy, and that is the part that must be true.
--
-- The SERIES is standing configuration -- it decides whose turn comes round --
-- so it is admin-only to write, matching maintenance_item and public.aircraft.
-- ---------------------------------------------------------------------------

alter table public.task        enable row level security;
alter table public.task_series enable row level security;

revoke all on public.task        from anon;
revoke all on public.task_series from anon;

create policy task_select_members on public.task
  for select to authenticated using (public.current_member_id() is not null);
-- Raised by you, or by an admin on someone's behalf. The recurring ones are
-- written by security definer functions and are not gated by this at all.
create policy task_insert_members on public.task
  for insert to authenticated
  with check (created_by = public.current_member_id() or public.is_admin());
create policy task_update_members on public.task
  for update to authenticated
  using (public.current_member_id() is not null)
  with check (public.current_member_id() is not null);
-- Deleting is for a task entered by mistake, so it stays with its author.
-- Everything else is cancelled, which keeps the record.
create policy task_delete_own on public.task
  for delete to authenticated using (created_by = public.current_member_id());
create policy task_admin_all on public.task
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy task_series_select_members on public.task_series
  for select to authenticated using (public.current_member_id() is not null);
create policy task_series_admin_write on public.task_series
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

comment on table public.task is
  'One admin chore, with one assignee. series_id null means a one-off.';
comment on column public.task.period_month is
  'The month this instance is about, not when it was created.';
comment on function public.task_next_assignee(uuid) is
  'Whose turn is next: the member after whoever COMPLETED the last one.';
