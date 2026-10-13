"use client";

import { useActionState } from "react";

type Failed = { error: string } | null;

/**
 * One button that calls a Server Action, with room for what it said if it
 * refused.
 *
 * ActionForm is the full-screen version: it owns a screen's layout and pins its
 * button to the bottom. These sit inside a list, where there are several of
 * them and each needs its own pending state and its own error -- "this draft
 * has no lines" belongs beside that draft, not at the foot of the page.
 */
export function InlineAction({
  action,
  label,
  fields,
  tone = "accent",
}: {
  action: (prev: Failed, form: FormData) => Promise<Failed>;
  label: string;
  fields?: Record<string, string>;
  tone?: "accent" | "outline";
}) {
  const [state, formAction, pending] = useActionState(action, null);

  return (
    <form action={formAction}>
      {Object.entries(fields ?? {}).map(([name, value]) => (
        <input key={name} type="hidden" name={name} value={value} />
      ))}

      <button
        type="submit"
        disabled={pending}
        className={`flex h-11 items-center justify-center rounded-[10px] px-4 text-[15px] font-semibold disabled:opacity-60 ${
          tone === "accent"
            ? "bg-accent text-white"
            : "border-[1.5px] border-ink bg-surface"
        }`}
      >
        {pending ? "Working…" : label}
      </button>

      {state?.error && (
        <p
          role="alert"
          className="mt-2 rounded-[10px] border border-snag-line bg-snag px-3 py-2.5 text-[13px] font-medium text-snag-text"
        >
          {state.error}
        </p>
      )}
    </form>
  );
}
