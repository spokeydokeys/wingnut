import { requireMember } from "@/lib/dal";
import { signOut } from "@/app/auth/actions";

export const dynamic = "force-dynamic";

/**
 * Placeholder. The flight timer that belongs here arrives with the timer
 * migration; for now this exists to prove the auth boundary end to end.
 */
export default async function Home() {
  const member = await requireMember();

  return (
    <main className="mx-auto flex w-full max-w-md flex-1 flex-col gap-4 p-6">
      <h1 className="text-2xl font-semibold">Wingnut</h1>
      <p className="text-sm">
        Signed in as {member.full_name} ({member.email}) &mdash; {member.role}.
      </p>
      <form action={signOut}>
        <button type="submit" className="text-sm underline">
          Sign out
        </button>
      </form>
    </main>
  );
}
