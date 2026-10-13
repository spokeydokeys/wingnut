import { redirect } from "next/navigation";

import { verifySession, getCurrentMember } from "@/lib/dal";
import { signOut } from "@/app/auth/actions";

export const dynamic = "force-dynamic";

/**
 * Signed in, but the email is not on the owner roster. Deliberately vague: it
 * does not say whether the address exists, only that it has no access.
 */
export default async function NoAccessPage() {
  const user = await verifySession();
  if (!user) redirect("/login");
  if (await getCurrentMember()) redirect("/");

  return (
    <main className="mx-auto flex w-full max-w-sm flex-1 flex-col justify-center gap-4 p-6">
      <h1 className="text-2xl font-semibold">No access</h1>
      <p className="text-sm opacity-70">
        {user.email} is not set up as an owner. Ask an admin to add it to the
        roster, then sign in again.
      </p>
      <form action={signOut}>
        <button type="submit" className="text-sm underline">
          Sign out
        </button>
      </form>
    </main>
  );
}
