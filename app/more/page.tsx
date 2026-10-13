import Link from "next/link";

import { signOut } from "@/app/auth/actions";
import { TabBar } from "@/components/tab-bar";
import { requireMember } from "@/lib/dal";

export const dynamic = "force-dynamic";

/**
 * Everything one level down. SPEC.md 3 puts bookings, reserves, places,
 * ownership and the Shortcut token here rather than on a tab of their own.
 * Only sign-out is built; the rest arrive with their phases.
 */
export default async function More() {
  const member = await requireMember();

  return (
    <>
      <header className="flex-none px-4 pt-5 pb-1">
        <h1 className="text-[26px] font-semibold">More</h1>
      </header>

      <main className="flex min-h-0 flex-1 flex-col gap-3 px-4 pt-3">
        <div className="rounded-[14px] border border-line bg-surface p-3.5">
          <div className="field-label">Signed in as</div>
          <div className="text-base font-semibold">{member.full_name}</div>
          <div className="text-[13px] text-muted">
            {member.email} · {member.role}
          </div>
        </div>

        <Link
          href="/tasks"
          className="flex items-center justify-between rounded-[14px] border border-line bg-surface p-3.5"
        >
          <span>
            <span className="block text-base font-semibold">Tasks and chores</span>
            <span className="block text-[13px] text-muted">
              Whose turn the admin is, and what is still outstanding
            </span>
          </span>
          <svg
            aria-hidden="true"
            width="24"
            height="24"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path d="M9 5l7 7-7 7" />
          </svg>
        </Link>

        <Link
          href="/more/places"
          className="flex items-center justify-between rounded-[14px] border border-line bg-surface p-3.5"
        >
          <span>
            <span className="block text-base font-semibold">Saved places</span>
            <span className="block text-[13px] text-muted">
              Rename a dock, or add one before you fly there
            </span>
          </span>
          <svg
            aria-hidden="true"
            width="24"
            height="24"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path d="M9 5l7 7-7 7" />
          </svg>
        </Link>

        <p className="rounded-[14px] border border-line bg-surface p-3.5 text-[15px] text-muted">
          Bookings, reserves, ownership shares and the iOS Shortcut token will
          appear here as those phases land.
        </p>

        <form action={signOut}>
          <button
            type="submit"
            className="flex h-12 w-full items-center justify-center rounded-xl border-[1.5px] border-ink bg-surface text-base font-semibold"
          >
            Sign out
          </button>
        </form>
      </main>

      <TabBar />
    </>
  );
}
