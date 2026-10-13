-- Linking a verified auth user to their member row.
--
-- Members are created by an admin ahead of time (the roster is the four
-- owners, not the open internet). Signing in therefore does not create a
-- member; it *claims* one, by matching the verified email on the session token
-- to member.email. An email that is not on the roster gets no member row and
-- so no access to anything, which is the behaviour we want: invite-only.
--
-- Everything here derives identity from the session token, never from an
-- argument, so a caller cannot ask to be linked to someone else's row.

-- ---------------------------------------------------------------------------
-- The email on the verified session token.
--
-- Reads the same request.jwt.claims GUC that auth.uid() does, so self-hosting
-- needs nothing beyond the existing shim in scripts/selfhost-shim.sql.
-- ---------------------------------------------------------------------------

create function public.current_auth_email()
returns text
language sql
stable
set search_path = ''
as $$
  select lower(nullif(
    coalesce(
      current_setting('request.jwt.claim.email', true),
      current_setting('request.jwt.claims', true)::jsonb ->> 'email'
    ),
    ''
  ));
$$;

-- ---------------------------------------------------------------------------
-- Claim the member row matching the caller's verified email.
--
-- Idempotent: once linked it just returns the member id, so the app can call
-- it on every sign-in without caring whether this is the first one. Returns
-- null when the email is not on the roster, which the app treats as "no
-- access" rather than an error.
-- ---------------------------------------------------------------------------

create function public.claim_member_identity()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth_id uuid := auth.uid();
  v_email   text;
  v_member  uuid;
begin
  if v_auth_id is null then
    raise exception 'not authenticated';
  end if;

  select m.id into v_member
  from public.member m
  where m.auth_user_id = v_auth_id;

  if v_member is not null then
    return v_member;
  end if;

  v_email := public.current_auth_email();
  if v_email is null then
    raise exception 'session token carries no email claim';
  end if;

  -- auth_user_id is null guards against stealing an already-claimed row even
  -- if two member rows somehow shared an email.
  update public.member m
     set auth_user_id = v_auth_id
   where lower(m.email) = v_email
     and m.auth_user_id is null
     and m.is_active
  returning m.id into v_member;

  return v_member;
end;
$$;

revoke all on function public.claim_member_identity() from public;
grant execute on function public.claim_member_identity() to authenticated;

revoke all on function public.current_auth_email() from public;
grant execute on function public.current_auth_email() to authenticated;

-- ---------------------------------------------------------------------------
-- Let a member claim their own unclaimed row.
--
-- The original guard made auth_user_id admin-only, which would mean an admin
-- has to be present for every first sign-in. Widen it by exactly one case: a
-- previously unclaimed row may be pointed at the caller's own verified auth
-- id. You can still never point a row at anybody else, and never re-point a
-- row that is already claimed.
-- ---------------------------------------------------------------------------

create or replace function public.guard_member_privileged_columns()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role is distinct from old.role and not public.is_admin() then
    raise exception 'only an admin may change a member role';
  end if;

  -- coalesce, not bare comparison: auth.uid() is null for an unauthenticated
  -- caller, and `new.auth_user_id = null` is NULL, which would make the whole
  -- condition NULL and silently skip the RAISE.
  if new.auth_user_id is distinct from old.auth_user_id
     and not public.is_admin()
     and not coalesce(
           old.auth_user_id is null and new.auth_user_id = auth.uid(),
           false)
  then
    raise exception 'only an admin may change the auth mapping';
  end if;

  if new.is_active is distinct from old.is_active and not public.is_admin() then
    raise exception 'only an admin may activate or deactivate a member';
  end if;

  return new;
end;
$$;
