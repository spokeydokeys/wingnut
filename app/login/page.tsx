import { redirect } from "next/navigation";

import { verifySession } from "@/lib/dal";
import { MagicLinkForm } from "./magic-link-form";

export const dynamic = "force-dynamic";

const LINK_ERRORS: Record<string, string> = {
  link_invalid: "That sign-in link was malformed. Ask for a new one.",
  link_expired: "That sign-in link has expired or was already used.",
};

export default async function LoginPage({
  searchParams,
}: PageProps<"/login">) {
  if (await verifySession()) redirect("/");

  // Next 16: searchParams is a Promise.
  const { error } = await searchParams;
  const message = typeof error === "string" ? LINK_ERRORS[error] : undefined;

  return (
    <main className="mx-auto flex w-full max-w-sm flex-1 flex-col justify-center gap-6 p-6">
      <div>
        <h1 className="text-2xl font-semibold">Wingnut</h1>
        <p className="text-sm opacity-70">
          Sign in with the email address you were added with. No password.
        </p>
      </div>

      {message ? (
        <p role="alert" className="text-sm text-red-600">
          {message}
        </p>
      ) : null}

      <MagicLinkForm />
    </main>
  );
}
