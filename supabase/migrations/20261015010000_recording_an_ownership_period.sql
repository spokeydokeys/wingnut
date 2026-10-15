-- Recording a new ownership split, all of it or none of it.
--
-- A period and its holdings are two inserts, and PostgREST cannot put two
-- requests in one transaction. Done from the client, a failure between them
-- leaves a period with no shares in it -- and that is not a harmless empty row:
-- `ownership_as_of` picks the newest period on or before the date asked about,
-- so an empty newest period makes every owner's `fixed_cost_share` zero and the
-- hangarage silently stops being billed to anybody.
--
-- Hence one function and one statement from the caller. Security INVOKER, not
-- definer: `ownership_period_admin_write` and `ownership_share_admin_write` are
-- still the rule about who may do this, and a role check written here would be
-- a second copy of it that can fall out of step.

create function public.record_ownership_period(
  p_aircraft_id    uuid,
  p_effective_from date,
  p_note           text,
  p_member_ids     uuid[],
  p_shares         integer[]
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_period uuid;
  v_want   integer;
  v_total  bigint;
begin
  if coalesce(array_length(p_member_ids, 1), 0)
     is distinct from coalesce(array_length(p_shares, 1), 0) then
    raise exception 'every holder needs exactly one share figure';
  end if;

  select c.total_shares into v_want
  from public.aircraft a
  join public.company c on c.id = a.company_id
  where a.id = p_aircraft_id;

  if v_want is null then
    raise exception 'that aeroplane could not be found';
  end if;

  if exists (select 1 from unnest(p_shares) s where s < 0) then
    raise exception 'a holding cannot be negative';
  end if;

  -- The deferred constraint trigger would catch a bad total at commit anyway.
  -- This says the same thing before anything is written, and says it with both
  -- numbers in it, so the caller can put them in front of whoever typed them.
  select coalesce(sum(s), 0) into v_total from unnest(p_shares) s;
  if v_total <> v_want then
    raise exception 'ownership shares sum to %, must be %', v_total, v_want;
  end if;

  insert into public.ownership_period (aircraft_id, effective_from, note)
  values (p_aircraft_id, p_effective_from, nullif(btrim(p_note), ''))
  returning id into v_period;

  insert into public.ownership_share (period_id, member_id, shares)
  select v_period, t.m, t.s
  from unnest(p_member_ids, p_shares) as t(m, s);

  return v_period;
end;
$$;

comment on function public.record_ownership_period is
  'Writes an ownership period and its holdings in one transaction. Runs as the '
  'caller, so the admin-write policies on both tables decide who may do it.';
