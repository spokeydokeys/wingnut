/**
 * Receipt images: the one place that knows where the bytes live.
 *
 * THIS IS THE SEAM. Data portability is a hard requirement for this project,
 * and object storage is the part of Supabase with no plain-Postgres equivalent
 * to fall back on. So everything that is Supabase-shaped about receipt images
 * is in this module, and the rest of the app goes through it.
 *
 * What that buys: moving to S3, MinIO or a directory on a disk means
 * reimplementing these four functions against a different SDK and copying a
 * folder of files. No column changes, no backfill, no string surgery across
 * years of rows.
 *
 * What makes that possible is the rule that `public.expense.receipt_key` holds
 * an object KEY and never a URL. A URL in a column bakes the hostname, the
 * bucket name and the signing scheme into the data; a key is just a path, and a
 * path is portable. Nothing outside this file should build a URL either -- call
 * `receiptUrl()` and get one that expires.
 *
 * Deliberately client-agnostic: it takes a SupabaseClient rather than making
 * one, so the same code serves the browser (which uploads with the member's own
 * JWT, straight to storage, no Server Action on the path) and the server (which
 * mints view URLs while rendering). That is also why there is no
 * `import "server-only"` here.
 */

import type { SupabaseClient } from "@supabase/supabase-js";

import type { Database } from "./database.types";

type Client = SupabaseClient<Database>;

/** Created by `20261013235900_receipt_storage.sql`. Private. */
export const RECEIPT_BUCKET = "receipts";

/**
 * What a phone camera produces and the detail screen can render.
 *
 * Kept in step with the bucket's `allowed_mime_types`: this list is the polite
 * refusal, that one is the enforced one. No PDFs -- see the migration.
 */
export const RECEIPT_MIME_TYPES = ["image/jpeg", "image/png", "image/webp"];

/**
 * The bucket's own limit is 10 MB. Resizing to 1600px (SPEC.md 4.7) lands a
 * phone photo around 200-400 KB, so hitting this means the resize did not run.
 */
export const RECEIPT_MAX_BYTES = 10 * 1024 * 1024;

/** How long a view URL lives. Long enough to look at, short enough to leak. */
const RECEIPT_URL_TTL_SECONDS = 60 * 60;

const EXTENSION_BY_MIME: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};

/**
 * `receipt/<company>/<yyyy>/<mm>/<expense-id>.<ext>`
 *
 * The month is in the path on purpose. "Give me the 2026 receipts for the
 * auditor" is then a prefix listing instead of a join against the database,
 * which matters most in the case where you have lost the database. The expense
 * id as the filename makes an orphaned object traceable back to its row, and
 * makes re-uploading over a rejected receipt overwrite rather than accumulate.
 *
 * `spentOn` is a plain `yyyy-mm-dd` date string, as stored -- not a Date.
 * Parsing it to a Date and asking for the month would apply the runtime's zone
 * and file a receipt from the 1st under the previous month.
 */
export function receiptObjectKey(args: {
  companyId: string;
  spentOn: string;
  expenseId: string;
  contentType: string;
}): string {
  const extension = EXTENSION_BY_MIME[args.contentType];
  if (!extension) {
    throw new Error(`receipts cannot hold ${args.contentType}`);
  }

  const [year, month] = args.spentOn.split("-");
  if (!year || !month) {
    throw new Error(`spentOn must be yyyy-mm-dd, got ${args.spentOn}`);
  }

  return `receipt/${args.companyId}/${year}/${month}/${args.expenseId}.${extension}`;
}

/**
 * Put the image in the bucket.
 *
 * `upsert` is on because the one thing a member does repeatedly is retake a
 * blurry photo of the same receipt, and the key is derived from the expense id
 * so the retake has the same key. Once the expense is approved the bucket
 * refuses the overwrite itself (`receipt_replace_until_approved`), which is the
 * check that actually matters and the one the browser cannot talk its way past.
 */
export async function uploadReceipt(
  supabase: Client,
  objectKey: string,
  file: Blob,
): Promise<{ error: string | null }> {
  if (file.size > RECEIPT_MAX_BYTES) {
    return { error: "That image is too large. Try again with a smaller photo." };
  }

  const { error } = await supabase.storage
    .from(RECEIPT_BUCKET)
    .upload(objectKey, file, {
      contentType: file.type,
      upsert: true,
    });

  return { error: error ? error.message : null };
}

/**
 * A URL that works for an hour.
 *
 * The bucket is private, so there is no stable URL to store and none to leak.
 * Minted per render: one round trip to show a receipt is the price of the
 * image not being readable by anyone who guesses an expense id.
 */
export async function receiptUrl(
  supabase: Client,
  objectKey: string,
): Promise<string | null> {
  const { data, error } = await supabase.storage
    .from(RECEIPT_BUCKET)
    .createSignedUrl(objectKey, RECEIPT_URL_TTL_SECONDS);

  if (error || !data) return null;
  return data.signedUrl;
}

/**
 * Drop the image.
 *
 * Only reachable while the expense is still editable: the bucket's
 * `receipt_delete_until_approved` policy refuses once it is approved, because
 * by then the picture is the evidence behind a credit that is agreed and may
 * already be on an issued invoice.
 */
export async function deleteReceipt(
  supabase: Client,
  objectKey: string,
): Promise<{ error: string | null }> {
  const { error } = await supabase.storage
    .from(RECEIPT_BUCKET)
    .remove([objectKey]);

  return { error: error ? error.message : null };
}
