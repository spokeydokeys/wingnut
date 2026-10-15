-- The roster must never run out of active admins.
--
-- Giving an admin the People screen also gives them the two buttons that can
-- lock everybody out: demote the only admin, or deactivate them. There is no
-- recovery from inside the app -- only an admin may change a role, so once
-- there are none left the only way back is psql, which is precisely what the
-- People screen was built to stop being necessary.
--
-- This is in the database rather than in the Server Action because the action
-- is not the only way in: PostgREST exposes `member` directly, and
-- `member_admin_write` would happily accept the update. A rule that only one
-- caller obeys is not a rule.

create function public.assert_an_admin_remains()
returns trigger
language plpgsql
security definer           -- so the count is of the table, not of what RLS
set search_path = ''       -- lets the caller see
as $$
begin
  if not exists (
    select 1
    from public.member m
    where m.is_active
      and m.role = 'admin'::public.member_role
  ) then
    raise exception 'the roster must keep at least one active admin';
  end if;

  return null;
end;
$$;

-- Per statement, not per row: a single update that demotes two admins at once
-- is one question ("is anybody left?"), and asking it per row would answer it
-- against a half-applied statement.
--
-- Not deferred, so the refusal arrives on the statement that caused it rather
-- than at commit. The cost is that swapping the only admin has to promote the
-- newcomer before demoting the incumbent, which is the safer order anyway.
create trigger member_keeps_an_admin
  after update or delete on public.member
  for each statement execute function public.assert_an_admin_remains();
