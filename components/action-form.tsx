"use client";

import type { ReactNode } from "react";
import { useActionState } from "react";

type Failed = { error: string } | null;

/**
 * A form that submits to a Server Action and shows what it said if it refused.
 *
 * The fields are passed in as children and rendered on the server, so adding a
 * screen does not add a client bundle; the only thing that has to be
 * interactive is the pending state and the error, which is all this holds.
 *
 * On success the action redirects and never returns, so anything in `state` is
 * a refusal worth putting in front of the person who typed it.
 */
export function ActionForm({
  action,
  submitLabel,
  children,
}: {
  action: (prev: Failed, form: FormData) => Promise<Failed>;
  submitLabel: string;
  children: ReactNode;
}) {
  const [state, formAction, pending] = useActionState(action, null);

  return (
    <form action={formAction} className="flex min-h-0 flex-1 flex-col gap-3.5">
      {children}

      {state?.error && (
        <p
          role="alert"
          className="rounded-[10px] border border-snag-line bg-snag px-3 py-2.5 text-[13px] font-medium text-snag-text"
        >
          {state.error}
        </p>
      )}

      <div className="flex-1" />

      <button
        type="submit"
        disabled={pending}
        className="flex h-14 flex-none items-center justify-center rounded-[14px] bg-accent text-lg font-semibold text-white disabled:opacity-60"
      >
        {pending ? "Saving…" : submitLabel}
      </button>
    </form>
  );
}
