-- The receipts bucket.
--
-- THE ONE SUPABASE-SPECIFIC MIGRATION IN THIS REPO. Everything else is plain
-- PostgreSQL that restores onto a vanilla server; this file touches the
-- `storage` schema, which only exists because Supabase Storage put it there.
--
-- That is deliberate and it is contained:
--
--   - scripts/export-db.sh dumps --schema=public only, so nothing here is in
--     the export and nothing here has to restore. verify-restore.sh replays the
--     dump, not the migrations, so vanilla postgres:17 never sees this file.
--   - the application never imports from `storage` either. lib/storage.ts is
--     the seam: it holds object KEYS, mints short-lived signed URLs on demand,
--     and is the single file to rewrite for S3, MinIO or a disk.
--   - what is stored in public.expense is the key, never a URL. A URL in a
--     column is a migration that has to be done later with string surgery
--     across six years of rows.
--
-- So moving off Supabase means re-pointing one TypeScript module and copying a
-- directory of files, not restating any data.
--
-- Keys are shaped receipt/<company>/<yyyy>/<mm>/<expense-id>.<ext>, which
-- lib/storage.ts builds. The month in the path is what makes "give me the
-- 2026 receipts for the auditor" a prefix listing rather than a join.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'receipts',
  'receipts',
  -- PRIVATE. A receipt carries a vendor, a date, an amount and sometimes a
  -- card's last four digits. Public buckets serve any object to anyone who
  -- knows the key, and keys here are guessable from an expense id.
  false,
  -- A backstop, not the mechanism: the client resizes to 1600px before
  -- uploading (SPEC.md 4.7), which lands well under this. A phone that skipped
  -- the resize should be refused rather than fill the bucket.
  10485760,
  -- Images only. A PDF receipt would need a different viewer on the detail
  -- screen, and every receipt this app captures comes from a camera.
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Is this object's receipt already agreed?
--
-- security definer because the answer must not depend on what the caller can
-- see. A storage policy runs as the member doing the upload, and if their reach
-- into public.expense were ever narrowed the `not exists` below would come back
-- true and quietly unlock the originals. The lock has to be a property of the
-- receipt, not of who is asking.
--
-- Takes storage.objects.name (the key) because that is all a storage policy
-- has to work with; public.expense.receipt_key holds the same string.
-- ---------------------------------------------------------------------------

create function public.receipt_is_locked(p_object_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.expense e
    where e.receipt_key = p_object_key
      and e.status = 'approved'::public.expense_status
  );
$$;

comment on function public.receipt_is_locked(text) is
  'True once the expense pointing at this storage key has been approved. Used by the receipts bucket policies to refuse replacing or deleting the evidence behind an agreed reimbursement.';

revoke all on function public.receipt_is_locked(text) from anon;

-- ---------------------------------------------------------------------------
-- Who may touch an object
--
-- Reading is open to every active member, because approval is "the other
-- co-owner agrees" and you cannot agree to a receipt you cannot see.
--
-- The interesting rule is the last two: SPEC.md 4.7 says "lock the originals
-- once approved". That is enforced here rather than in the app because the
-- storage API is reached directly from the browser with the member's own JWT,
-- so a Server Action is not on the path at all and could not refuse it.
-- ---------------------------------------------------------------------------

create policy receipt_read_members on storage.objects
  for select to authenticated
  using (
    bucket_id = 'receipts'
    and public.current_member_id() is not null
  );

create policy receipt_upload_members on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'receipts'
    and public.current_member_id() is not null
  );

-- An approved receipt's image is evidence behind a reimbursement that has been
-- agreed and may already be on an issued invoice. The expense row is frozen by
-- expense_zz_guard_frozen; without this the picture it points at could still be
-- swapped for a different one.
create policy receipt_replace_until_approved on storage.objects
  for update to authenticated
  using (
    bucket_id = 'receipts'
    and public.current_member_id() is not null
    and not public.receipt_is_locked(name)
  )
  with check (
    bucket_id = 'receipts'
    and public.current_member_id() is not null
    and not public.receipt_is_locked(name)
  );

create policy receipt_delete_until_approved on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'receipts'
    and public.current_member_id() is not null
    and not public.receipt_is_locked(name)
  );
