"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";

import { attachReceipt, createExpense } from "@/app/receipts/actions";
import { FIELD } from "@/components/field";
import type { Category } from "@/lib/expenses";
import { shrinkImage } from "@/lib/image";
import { createClient } from "@/lib/supabase/browser";
import { RECEIPT_MIME_TYPES, uploadReceipt } from "@/lib/storage";

/**
 * Entering a receipt, photo and all.
 *
 * A client component rather than an ActionForm because the photo does not go
 * through the server: the browser uploads it straight to the bucket with the
 * member's own JWT, and that needs three steps in order (save the row, upload
 * to the key the row implies, point the row at it) which a plain `<form
 * action>` cannot express.
 *
 * The order matters and is not an implementation detail. The row goes in
 * FIRST, so a failed upload leaves a receipt that is merely missing its photo
 * rather than nothing at all. At a fuel dock on one bar of signal that is the
 * difference between a record and a lost $250.
 */
export function ReceiptForm({
  categories,
  defaultDate,
  memberName,
  flightId,
}: {
  categories: Category[];
  defaultDate: string;
  memberName: string;
  flightId?: string;
}) {
  const router = useRouter();

  const [photo, setPhoto] = useState<Blob | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  // Set when the row saved but its photo did not. The receipt exists, so this
  // is not a failure to be retried by resubmitting -- it is somewhere to go.
  const [savedWithoutPhoto, setSavedWithoutPhoto] = useState<string | null>(null);

  async function choosePhoto(file: File | undefined) {
    if (!file) return;
    setError(null);
    const blob = await shrinkImage(file);
    setPhoto(blob);
    setPreview((old) => {
      if (old) URL.revokeObjectURL(old);
      return URL.createObjectURL(blob);
    });
  }

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy) return;

    setError(null);
    setSavedWithoutPhoto(null);
    setBusy("Saving…");

    const form = new FormData(event.currentTarget);
    if (photo) form.set("content_type", photo.type);

    const created = await createExpense(form);
    if ("error" in created) {
      setError(created.error);
      setBusy(null);
      return;
    }

    if (photo && created.objectKey) {
      setBusy("Uploading the photo…");

      // Caught, not left to escape: everything from here on is about the
      // photo, the receipt itself is already saved, and an unhandled rejection
      // would leave the button disabled on "Uploading the photo…" forever with
      // no way to find out that the row went in.
      let uploaded = false;
      try {
        const put = await uploadReceipt(createClient(), created.objectKey, photo);
        uploaded = put.error === null && (await attachReceipt(created.id, photo.type)) === null;
      } catch {
        uploaded = false;
      }

      if (!uploaded) {
        setSavedWithoutPhoto(created.id);
        setBusy(null);
        return;
      }
    }

    router.push(`/receipts/${created.id}`);
  }

  if (savedWithoutPhoto) {
    return (
      <div className="flex flex-col gap-3.5">
        <p
          role="alert"
          className="rounded-[10px] border border-snag-line bg-snag px-3 py-2.5 text-[13px] font-medium text-snag-text"
        >
          The receipt is saved, but the photo did not upload. Open it and add
          the photo when you have signal — it cannot be agreed to without one.
        </p>
        <Link
          href={`/receipts/${savedWithoutPhoto}`}
          className="flex h-14 items-center justify-center rounded-[14px] bg-accent text-lg font-semibold text-white"
        >
          Open the receipt
        </Link>
      </div>
    );
  }

  return (
    <form onSubmit={submit} className="flex flex-col gap-3.5">
      {flightId && <input type="hidden" name="flight_id" value={flightId} />}

      <label className="flex flex-col gap-1.5">
        <span className="field-label">Photo of the receipt</span>
        {preview ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={preview}
            alt="The receipt you just photographed"
            className="max-h-64 w-full rounded-[10px] border border-field object-contain"
          />
        ) : (
          <span className="flex h-24 items-center justify-center rounded-[10px] border border-dashed border-field text-[15px] text-muted">
            Take a photo, or carry on without one
          </span>
        )}
        {/*
          `capture` opens the camera rather than the gallery on a phone, which
          is where a receipt is nearly always photographed. On a desktop it is
          ignored and this is an ordinary file picker.
        */}
        <input
          type="file"
          accept={RECEIPT_MIME_TYPES.join(",")}
          capture="environment"
          onChange={(e) => choosePhoto(e.target.files?.[0])}
          className="mt-1.5 text-[15px]"
        />
      </label>

      <label className="flex flex-col gap-1.5">
        <span className="field-label">Who paid</span>
        <select name="payer" defaultValue="member" className={FIELD}>
          <option value="member">{memberName} — pay me back</option>
          <option value="company">The company card</option>
        </select>
      </label>

      <label className="flex flex-col gap-1.5">
        <span className="field-label">Bought from</span>
        <input
          name="vendor"
          required
          autoComplete="off"
          placeholder="Esso Nanaimo"
          className={FIELD}
        />
      </label>

      <div className="flex gap-3">
        <label className="flex flex-1 flex-col gap-1.5">
          <span className="field-label">Date</span>
          <input
            type="date"
            name="spent_on"
            defaultValue={defaultDate}
            required
            className={FIELD}
          />
        </label>

        <label className="flex flex-1 flex-col gap-1.5">
          <span className="field-label">Total paid</span>
          {/*
            inputMode decimal, not type=number: a number spinner on a phone is
            a scroll hazard beside a dollar figure, and `step` validation would
            reject the comma a Canadian keyboard sometimes offers.
          */}
          <input
            name="total_amount"
            inputMode="decimal"
            required
            placeholder="248.60"
            className={`${FIELD} numeric`}
          />
        </label>
      </div>

      <label className="flex flex-col gap-1.5">
        <span className="field-label">What it was for</span>
        <select name="gl_account_code" required className={FIELD}>
          {categories.map((category) => (
            <option key={category.code} value={category.code}>
              {category.name}
            </option>
          ))}
        </select>
      </label>

      <label className="flex flex-col gap-1.5">
        <span className="field-label">Litres (fuel only)</span>
        <input
          name="litres"
          inputMode="decimal"
          placeholder="134.40"
          className={`${FIELD} numeric`}
        />
      </label>

      <label className="flex flex-col gap-1.5">
        <span className="field-label">Note</span>
        <textarea
          name="note"
          rows={2}
          placeholder="Topped up both tanks after the Bay run."
          className={`${FIELD} h-auto py-2.5`}
        />
      </label>

      {/*
        Folded away because the company is not GST registered yet, so neither
        of these does anything today. They are here rather than added later
        because the paper will be long gone by the time it registers, and a
        receipt whose tax was never captured cannot be gone back to.
      */}
      <details className="rounded-[10px] border border-field px-3 py-2.5">
        <summary className="field-label cursor-pointer">Tax on the receipt</summary>
        <div className="mt-2.5 flex flex-col gap-3">
          <label className="flex flex-col gap-1.5">
            <span className="field-label">GST included in the total</span>
            <input
              name="gst_amount"
              inputMode="decimal"
              placeholder="0.00"
              className={`${FIELD} numeric`}
            />
          </label>
          <label className="flex flex-col gap-1.5">
            <span className="field-label">Their GST number</span>
            <input name="vendor_gst_number" autoComplete="off" className={FIELD} />
          </label>
        </div>
      </details>

      {error && (
        <p
          role="alert"
          className="rounded-[10px] border border-snag-line bg-snag px-3 py-2.5 text-[13px] font-medium text-snag-text"
        >
          {error}
        </p>
      )}

      <button
        type="submit"
        disabled={busy !== null}
        className="flex h-14 flex-none items-center justify-center rounded-[14px] bg-accent text-lg font-semibold text-white disabled:opacity-60"
      >
        {busy ?? "Save the receipt"}
      </button>
    </form>
  );
}
