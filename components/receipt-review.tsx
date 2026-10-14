"use client";

import { useState, useTransition } from "react";

import { approveExpense, rejectExpense } from "@/app/receipts/actions";
import { FIELD } from "@/components/field";

/**
 * The decision: agree to the reimbursement, or decline it and say why.
 *
 * Declining is behind a second tap rather than sitting beside Agree as an
 * equal. The two are not equals: one of them tells the other owner their $250
 * is not coming back, and a mis-tap on a phone should not be able to do that.
 * The reason field is also why this is a client component -- it has to appear
 * without losing the page, and it is required, so the button cannot submit
 * until there is something in it.
 */
export function ReceiptReview({ expenseId }: { expenseId: string }) {
  const [declining, setDeclining] = useState(false);
  const [note, setNote] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function decline() {
    setError(null);
    const form = new FormData();
    form.set("review_note", note);
    startTransition(async () => {
      // On success the action redirects to the list and never returns, so
      // anything that comes back is a refusal worth showing.
      const result = await rejectExpense(expenseId, form);
      if (result?.error) setError(result.error);
    });
  }

  return (
    <div className="flex flex-none flex-col gap-2.5 rounded-[14px] border-[1.5px] border-ink bg-surface px-3.5 py-3">
      <p className="text-[15px] font-medium">
        This one is waiting on you. Agreeing to it puts the full amount back on
        their next bill as a credit.
      </p>

      <form action={approveExpense.bind(null, expenseId)}>
        <button
          type="submit"
          disabled={pending}
          className="flex h-12 w-full items-center justify-center rounded-[10px] bg-accent text-base font-semibold text-white disabled:opacity-60"
        >
          Agree to it
        </button>
      </form>

      {declining ? (
        <>
          <label className="flex flex-col gap-1.5">
            <span className="field-label">Why not</span>
            <textarea
              rows={2}
              value={note}
              onChange={(event) => setNote(event.target.value)}
              placeholder="So it can be put right"
              className={`${FIELD} h-auto py-2.5`}
            />
          </label>
          <button
            type="button"
            onClick={decline}
            disabled={pending || note.trim() === ""}
            className="flex h-12 items-center justify-center rounded-[10px] border-[1.5px] border-ink text-base font-semibold disabled:opacity-60"
          >
            {pending ? "Saving…" : "Send it back"}
          </button>
        </>
      ) : (
        <button
          type="button"
          onClick={() => setDeclining(true)}
          className="flex min-h-11 items-center justify-center text-[15px] font-medium text-muted underline"
        >
          Something is wrong with it
        </button>
      )}

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
