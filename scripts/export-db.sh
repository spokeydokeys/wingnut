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
#   MANIFEST.txt   what was taken, from where, with what versions
#
# pg_dump runs inside a postgres container matching the server major version,
# so nothing needs installing on the host.
#
# auth.users is exported as CSV rather than SQL on purpose: password hashes and
# refresh tokens are specific to the auth provider and worthless elsewhere. The
# durable link between an auth user and a member is the email address, so that
# is all a future provider needs in order to re-link accounts.

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
run_pg pg_dump "$DB_URL" \
  --schema=public \
  --no-owner \
  --no-privileges \
  --quote-all-identifiers \
  > "$out_dir/public.sql"

echo "  - auth user identities"
run_pg psql "$DB_URL" --no-psqlrc --quiet \
  -c "\copy (select id, email, created_at from auth.users order by created_at) to stdout with csv header" \
  > "$out_dir/auth_users.csv"

server_version="$(run_pg psql "$DB_URL" --no-psqlrc --quiet -tAc 'show server_version')"

{
  echo "Wingnut data export"
  echo "taken_at_utc:    $stamp"
  echo "server_version:  $server_version"
  echo "pg_dump_image:   $PG_IMAGE"
  echo "source_host:     $(printf '%s' "$DB_URL" | sed -E 's#//[^@]*@#//***@#')"
  echo "public_sql_bytes: $(wc -c < "$out_dir/public.sql")"
  echo "auth_users_rows:  $(($(wc -l < "$out_dir/auth_users.csv") - 1))"
  echo
  echo "To restore onto vanilla PostgreSQL (target must be an EMPTY database;"
  echo "public.sql recreates the public schema and will not merge into an"
  echo "existing one):"
  echo "  psql \"\$TARGET\" -f scripts/selfhost-shim.sql   # roles + auth.uid()"
  echo "  psql \"\$TARGET\" -c 'drop schema if exists public cascade'"
  echo "  psql \"\$TARGET\" -f public.sql"
  echo "Then re-invite users by the emails in auth_users.csv and repoint"
  echo "public.member.auth_user_id at the new provider's user ids."
} > "$out_dir/MANIFEST.txt"

echo
cat "$out_dir/MANIFEST.txt"
