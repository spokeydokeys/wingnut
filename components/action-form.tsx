"use client";

import type { ReactNode } from "react";
import { useActionState, useEffect, useRef } from "react";

type Failed = { error: string } | null;

/**
 * A form that submits to a Server Action and shows what it said if it refused.
 *
 * The fields are passed in as children and rendered on the server, so adding a
 * screen does not add a client bundle; the only thing that has to be
 * interactive is the pending state and the error, which is all this holds.
 *
 * On success the action redirects and never returns, so anything in `state` is
 * a refusal worth putting in front of the person who typed it -- along with
 * everything they typed, which takes the work in `restore` below.
 */
export function ActionForm({
  action,
  submitLabel,
  children,
  footer,
}: {
  action: (prev: Failed, form: FormData) => Promise<Failed>;
  submitLabel: string;
  children: ReactNode;
  /**
   * Rendered under the submit button. For the way out of a screen whose only
   * purpose is to be agreed to -- it has to be next to the thing it is an
   * alternative to, and the submit button is pinned to the bottom, so there is
   * nowhere else for it to go.
   */
  footer?: ReactNode;
}) {
  const [state, formAction, pending] = useActionState(action, null);

  const form = useRef<HTMLFormElement>(null);
  const typed = useRef<FormData | null>(null);

  /*
    React clears an uncontrolled form once its action settles, and these
    actions only settle when they refuse -- a success redirects and never
    comes back. So the reset lands on exactly one person: the one who got
    something wrong, who is then asked to retype the lot to fix one field.

    Putting it back by hand, rather than submitting by hand, keeps the two
    things `action={formAction}` gives us: the form still works before the
    page has hydrated, and the submit button still knows it is saving. Both
    were quietly lost by the obvious fix of calling the action from onSubmit.
  */
  useEffect(() => {
    const fields = form.current;
    const was = typed.current;
    if (!state?.error || !fields || !was) return;

    for (const field of fields.elements) {
      if (
        !(field instanceof HTMLInputElement) &&
        !(field instanceof HTMLSelectElement) &&
        !(field instanceof HTMLTextAreaElement)
      ) {
        continue;
      }
      if (!field.name) continue;

      if (
        field instanceof HTMLInputElement &&
        (field.type === "checkbox" || field.type === "radio")
      ) {
        // An unticked box submits nothing at all, so this is read the other
        // way round: it was ticked if its own value came back.
        field.checked = was.getAll(field.name).includes(field.value);
        continue;
      }

      // A file input cannot be assigned to, and a hidden one is written by
      // the server on every render, so neither needs anything doing.
      if (field.type === "file" || field.type === "hidden") continue;

      const value = was.get(field.name);
      if (typeof value === "string") field.value = value;
    }
  }, [state]);

  return (
    <form
      ref={form}
      action={formAction}
      // Kept so the effect above has something to put back. React has already
      // read the form by the time this runs, so copying it is all this does.
      onSubmit={(event) => {
        typed.current = new FormData(event.currentTarget);
      }}
      className="flex min-h-0 flex-1 flex-col gap-3.5"
    >
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

      {footer}
    </form>
  );
}
