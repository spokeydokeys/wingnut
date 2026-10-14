"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

import { attachReceipt, plannedReceiptKey } from "@/app/receipts/actions";
import { shrinkImage } from "@/lib/image";
import { createClient } from "@/lib/supabase/browser";
import { RECEIPT_MIME_TYPES, uploadReceipt } from "@/lib/storage";

/**
 * The picture, and the way to put one there.
 *
 * A client component for the same reason the capture form is one: the bytes go
 * from the browser to the bucket with the member's own JWT and never through a
 * Server Action. This is the second half of that flow, reached when the first
 * half failed -- a receipt saved at a fuel dock with no signal arrives here
 * with a row and no photo, and cannot be agreed to until it has one.
 *
 * `url` is a signed URL minted by the server while rendering, good for an
 * hour. On a successful upload this asks the server for a fresh render rather
 * than swapping in the local blob: the thing worth showing is the object that
 * is actually in the bucket under the key the row now points at.
 */
export function ReceiptPhoto({
  expenseId,
  url,
  canChange,
}: {
  expenseId: string;
  url: string | null;
  /**
   * False once the receipt is agreed or its month is billed. The bucket's own
   * `receipt_replace_until_approved` policy is what enforces it; this only
   * decides whether to offer a control that would be refused.
   */
  canChange: boolean;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function upload(file: File | undefined) {
    if (!file || busy) return;
    setError(null);
    setBusy(true);

    try {
      const blob = await shrinkImage(file);

      const planned = await plannedReceiptKey(expenseId, blob.type);
      if ("error" in planned) {
        setError(planned.error);
        return;
      }

      const put = await uploadReceipt(createClient(), planned.objectKey, blob);
      if (put.error) {
        setError(put.error);
        return;
      }

      const attached = await attachReceipt(expenseId, blob.type);
      if (attached) {
        setError(attached.error);
        return;
      }

      router.refresh();
    } catch {
      setError("The photo did not upload. Try again when you have signal.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex flex-none flex-col gap-1.5">
      {url ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={url}
          alt="The receipt"
          className="max-h-80 w-full rounded-[14px] border border-line bg-surface object-contain"
        />
      ) : (
        <p className="flex h-28 items-center justify-center rounded-[14px] border border-dashed border-field px-3.5 text-center text-[15px] text-muted">
          {canChange
            ? "No photo yet. It cannot be agreed to without one."
            : // Not "no photo yet": an agreed receipt had one, or it could not
              // have been agreed. Saying otherwise here would accuse somebody
              // of approving a reimbursement with nothing behind it.
              "No photo to show."}
        </p>
      )}

      {canChange && (
        <label className="flex flex-col gap-1.5">
          <span className="field-label">
            {url ? "Replace the photo" : "Add the photo"}
          </span>
          <input
            type="file"
            accept={RECEIPT_MIME_TYPES.join(",")}
            capture="environment"
            disabled={busy}
            onChange={(event) => upload(event.target.files?.[0])}
            className="text-[15px]"
          />
        </label>
      )}

      {busy && <p className="text-[13px] text-muted">Uploading the photo…</p>}

      {error && (
        <p
          role="alert"
          className="rounded-[10px] border border-snag-line bg-snag px-3 py-2.5 text-[13px] font-medium text-snag-text"
        >
          {error}
        </p>
      )}
    </div>
  );
}
