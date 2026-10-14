#!/usr/bin/env bash
#
# Full data export, for backup and for leaving Supabase.
#
#   ./scripts/export-db.sh                       # local stack
#   ./scripts/export-db.sh "postgresql://..."    # hosted project
#
# Produces, under exports/<timestamp>/:
#   public.sql     the entire application schema and data
#   auth_users.csv id and email of each auth user
#   receipts.csv   inventory of every receipt image: key, size, checksum
#   receipts/      the image bytes themselves, when API credentials are given
#   MANIFEST.txt   what was taken, from where, with what versions
#
# pg_dump runs inside a postgres container matching the server major version,
# so nothing needs installing on the host.
#
# auth.users is exported as CSV rather than SQL on purpose: password hashes and
# refresh tokens are specific to the auth provider and worthless elsewhere. The
# durable link between an auth user and a member is the email address, so that
# is all a future provider needs in order to re-link accounts.
#
# Receipts are in two halves because the inventory and the bytes come from
# different places. The inventory is in the database and so is always reachable
# with the DB_URL already supplied; the bytes are behind the Storage API and
# need a service role key, which is not something to require of a routine
# nightly dump. Exporting the inventory unconditionally means a restore can
# always tell whether it is complete -- a missing image is then a known gap
# with a key to go and find, rather than a blank square somebody notices in a
# year's time.

set -euo pipefail

DB_URL="${1:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
PG_IMAGE="${PG_IMAGE:-postgres:17}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out_dir="$repo_root/exports/$stamp"
mkdir -p "$out_dir"

# --network host so a 127.0.0.1 URL reaches the local stack; harmless for remote.
run_pg() {
  docker run --rm --network host -e PGCONNECT_TIMEOUT=15 "$PG_IMAGE" "$@"
}

echo "Exporting to exports/$stamp"

echo "  - public schema and data"
# --extension=btree_gist because --schema=public alone does NOT carry it:
# extensions are database-scoped, so schema filtering drops them, and the
# restore then fails on booking_no_overlap with "data type uuid has no default
# operator class for access method gist". Naming it here rather than adding it
# to the self-host shim keeps the dump self-contained -- the export has to
# stand on its own in front of a DBA who was handed it and nothing else.
run_pg pg_dump "$DB_URL" \
  --schema=public \
  --extension=btree_gist \
  --no-owner \
  --no-privileges \
  --quote-all-identifiers \
  > "$out_dir/public.sql"

echo "  - auth user identities"
run_pg psql "$DB_URL" --no-psqlrc --quiet \
  -c "\copy (select id, email, created_at from auth.users order by created_at) to stdout with csv header" \
  > "$out_dir/auth_users.csv"

> "$out_dir/receipts.csv"
receipt_bytes_taken=0

# storage.objects is outside --schema=public, so this inventory is the only
# record of the images in the export. metadata->>'size' and ->>'eTag' are what
# Storage records at upload; the eTag is the object's MD5, which is what makes
# "did every file arrive?" answerable after a copy.
if run_pg psql "$DB_URL" --no-psqlrc --quiet -tAc \
     "select 1 from information_schema.tables
       where table_schema = 'storage' and table_name = 'objects'" \
     | grep -q 1; then
  echo "  - receipt inventory"
  run_pg psql "$DB_URL" --no-psqlrc --quiet \
    -c "\copy (select name,
                      coalesce(metadata->>'size', '') as bytes,
                      coalesce(metadata->>'mimetype', '') as mimetype,
                      btrim(coalesce(metadata->>'eTag', ''), '\"') as md5,
                      created_at
                 from storage.objects
                where bucket_id = 'receipts'
                order by name) to stdout with csv header" \
    > "$out_dir/receipts.csv"

  # The bytes, only if we were given a way to ask for them. Both of these are
  # secrets: pass them in the environment, never on the command line.
  if [[ -n "${SUPABASE_URL:-}" && -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
    echo "  - receipt images"
    while IFS=, read -r key _rest; do
      [[ -z "$key" ]] && continue
      dest="$out_dir/receipts/$key"
      mkdir -p "$(dirname "$dest")"
      curl --fail --silent --show-error \
        -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
        "${SUPABASE_URL%/}/storage/v1/object/receipts/$key" \
        -o "$dest"
      receipt_bytes_taken=$((receipt_bytes_taken + 1))
    done < <(tail -n +2 "$out_dir/receipts.csv")
  else
    echo "  - receipt images SKIPPED (set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY)"
  fi
fi

receipt_rows=0
if [[ -s "$out_dir/receipts.csv" ]]; then
  receipt_rows=$(($(wc -l < "$out_dir/receipts.csv") - 1))
fi

server_version="$(run_pg psql "$DB_URL" --no-psqlrc --quiet -tAc 'show server_version')"

{
  echo "Wingnut data export"
  echo "taken_at_utc:    $stamp"
  echo "server_version:  $server_version"
  echo "pg_dump_image:   $PG_IMAGE"
  echo "source_host:     $(printf '%s' "$DB_URL" | sed -E 's#//[^@]*@#//***@#')"
  echo "public_sql_bytes: $(wc -c < "$out_dir/public.sql")"
  echo "auth_users_rows:  $(($(wc -l < "$out_dir/auth_users.csv") - 1))"
  echo "receipts_listed:  $receipt_rows"
  echo "receipts_fetched: $receipt_bytes_taken"
  echo
  echo "To restore onto vanilla PostgreSQL (target must be an EMPTY database;"
  echo "public.sql recreates the public schema and will not merge into an"
  echo "existing one):"
  echo "  psql \"\$TARGET\" -f scripts/selfhost-shim.sql   # roles + auth.uid()"
  echo "  psql \"\$TARGET\" -c 'drop schema if exists public cascade'"
  echo "  psql \"\$TARGET\" -f public.sql"
  echo "Then re-invite users by the emails in auth_users.csv and repoint"
  echo "public.member.auth_user_id at the new provider's user ids."
  echo
  echo "Receipt images: public.expense.receipt_key holds the object key, and"
  echo "receipts/ mirrors those keys as a directory tree. Copy that tree to the"
  echo "new store under the same keys and rewrite lib/storage.ts to address it;"
  echo "no row changes. Check receipts.csv against the copy before trusting it."
} > "$out_dir/MANIFEST.txt"

echo
cat "$out_dir/MANIFEST.txt"
