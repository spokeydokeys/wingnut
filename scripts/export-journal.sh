#!/usr/bin/env bash
#
# General ledger journal export, for handing to an accountant or importing
# into QuickBooks Online / Xero.
#
#   ./scripts/export-journal.sh                              # everything, local
#   ./scripts/export-journal.sh 2026-01-01 2026-12-31        # a date range
#   ./scripts/export-journal.sh 2026-01-01 2026-12-31 "postgresql://..."
#
# Writes exports/journal-<from>_<to>.csv. Every ledger entry becomes a balanced
# pair of rows, so the debit_credit column must sum to zero over any complete
# export; the script checks that rather than trusting it.
#
# Only posted entries are included -- a draft month is never exported, because
# a draft invoice is a proposal and not yet a debt.
#
# This is the "export-first" half of the accounting decision: Wingnut is the
# operations and AR sub-ledger, the accounting system is the general ledger,
# and the flow is one-way. Nothing here writes back.

set -euo pipefail

FROM="${1:-1900-01-01}"
TO="${2:-2999-12-31}"
DB_URL="${3:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
PG_IMAGE="${PG_IMAGE:-postgres:17}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$repo_root/exports"
out_file="$repo_root/exports/journal-${FROM}_${TO}.csv"

run_psql() {
  docker run --rm --network host -e PGCONNECT_TIMEOUT=15 "$PG_IMAGE" \
    psql "$DB_URL" --no-psqlrc --quiet -v ON_ERROR_STOP=1 "$@"
}

# The journal cannot be built without these two, and a silently-null account
# code would produce rows no accounting system will accept.
unconfigured="$(run_psql -tAc "
  select string_agg(legal_name, ', ')
  from public.company
  where ar_account_code is null or bank_account_code is null;
")"
if [[ -n "${unconfigured//[[:space:]]/}" ]]; then
  echo "error: ar_account_code and bank_account_code are not set for: $unconfigured" >&2
  echo "       set them to the real codes from the accounting system first." >&2
  exit 1
fi

echo "Exporting journal $FROM .. $TO"

run_psql -c "\copy (
  select
    j.entry_date,
    j.invoice_number,
    m.full_name as member,
    j.kind,
    j.description,
    j.line_no,
    j.gl_account_code,
    g.name as gl_account_name,
    case when j.debit_credit > 0 then  j.debit_credit end as debit,
    case when j.debit_credit < 0 then -j.debit_credit end as credit,
    j.tax_treatment,
    j.ledger_entry_id
  from public.gl_journal j
  join public.member m on m.id = j.member_id
  left join public.gl_account g
    on g.company_id = j.company_id and g.code = j.gl_account_code
  where j.entry_date between date '$FROM' and date '$TO'
  order by j.entry_date, j.invoice_number nulls last, j.ledger_entry_id, j.line_no
) to stdout with csv header" > "$out_file"

# Balanced-books check. Any complete export must net to zero; a non-zero total
# means the journal view and the ledger have diverged.
imbalance="$(run_psql -tAc "
  select coalesce(sum(debit_credit), 0)
  from public.gl_journal
  where entry_date between date '$FROM' and date '$TO';
")"

rows=$(( $(wc -l < "$out_file") - 1 ))
echo "  $rows journal lines -> exports/$(basename "$out_file")"

if [[ "$(printf '%s' "$imbalance" | tr -d ' ')" != "0.00" && \
      "$(printf '%s' "$imbalance" | tr -d ' ')" != "0" ]]; then
  echo "error: journal does not balance over this range (net $imbalance)" >&2
  exit 1
fi
echo "  balanced: debits equal credits"
