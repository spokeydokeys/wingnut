"use client";

import { useActionState } from "react";

import { sendMagicLink, type LoginState } from "./actions";

export function MagicLinkForm() {
  const [state, formAction, pending] = useActionState<LoginState, FormData>(
    sendMagicLink,
    {},
  );

  if (state.sentTo) {
    return (
      <p className="text-sm">
        Check <span className="font-medium">{state.sentTo}</span> for a sign-in
        link. It is good for one hour.
      </p>
    );
  }

  return (
    <form action={formAction} className="flex flex-col gap-3">
      <label className="flex flex-col gap-1 text-sm">
        Email
        <input
          type="email"
          name="email"
          autoComplete="email"
          required
          autoFocus
          className="rounded border px-3 py-2 text-base"
        />
      </label>

      {state.error ? (
        <p role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      ) : null}

      <button
        type="submit"
        disabled={pending}
        className="rounded bg-black px-3 py-2 text-base text-white disabled:opacity-50"
      >
        {pending ? "Sending…" : "Email me a sign-in link"}
      </button>
    </form>
  );
}
