import Link from "next/link";

import { setActive, setRole } from "@/app/more/actions";
import { BackHeader } from "@/components/back-header";
import { Chip } from "@/components/chip";
import { InlineAction } from "@/components/inline-action";
import { requireAdmin } from "@/lib/dal";
import { getPeople } from "@/lib/people";

export const dynamic = "force-dynamic";

/**
 * The roster. Until now the only way to put somebody on it was psql.
 *
 * Admin only, and `member_admin_write` is what actually enforces that -- the
 * requireAdmin above only decides whether the screen is worth drawing. A pilot
 * who reached this URL would be shown a list (everyone can read the roster)
 * and refused every button on it, which is a worse screen than no screen.
 *
 * There is no delete. A member is referenced by every flight, invoice and
 * receipt behind them and `ownership_share.member_id` is `on delete restrict`,
 * so the only honest end for somebody who leaves is to stop being active.
 *
 * The one button deliberately missing is Retire on your own row. Demoting
 * yourself is a handover and is offered; deactivating yourself is a locked
 * door, because an inactive member fails `current_member_id()` and lands on
 * /no-access with no way back in. Another admin can still do it to you, which
 * is the case where somebody is actually leaving.
 *
 * Demoting yourself is offered, but not on the press: it is the only change
 * here you cannot reverse yourself afterwards, so it goes through
 * /more/people/step-down. Every other button on this screen is undone by the
 * button that replaces it, which is confirmation enough.
 */
export default async function People() {
  const me = await requireAdmin();
  const people = await getPeople();

  return (
    <>
      <BackHeader
        href="/more"
        label="More"
        title="People"
        subtitle="Who is on the roster, what they may do, and who is still to sign in."
        action={
          <Link
            href="/more/people/new"
            className="flex h-11 items-center rounded-[10px] border-[1.5px] border-ink bg-surface px-4 text-[15px] font-semibold"
          >
            + Person
          </Link>
        }
      />

      <main className="flex min-h-0 flex-1 flex-col gap-2.5 overflow-y-auto px-4 pt-3.5 pb-4">
        {people.map((person) => (
          <div
            key={person.id}
            className={`flex-none rounded-[14px] border bg-surface px-3.5 py-3 ${
              person.is_active ? "border-line" : "border-hairline opacity-60"
            }`}
          >
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <div className="text-base font-semibold">
                  {person.full_name}
                  {person.id === me.id && (
                    <span className="font-normal text-muted"> · you</span>
                  )}
                </div>
                <div className="truncate text-[13px] text-muted">{person.email}</div>
              </div>

              <span className="flex-none">
                <Chip tone="neutral">
                  {person.role === "admin" ? "Admin" : "Pilot"}
                </Chip>
              </span>
            </div>

            {/*
              Two different kinds of "not here". Never signed in is a job to
              finish -- the magic link is waiting for them; no longer active is
              a decision somebody made. Saying "Invited" for both would hide
              the difference behind one word.
            */}
            {(!person.auth_user_id || !person.is_active) && (
              <p className="mt-1.5 text-[13px] text-muted">
                {!person.is_active
                  ? "No longer active. Their flights and invoices are untouched."
                  : "Has not signed in yet. Sending them the sign-in link finishes it."}
              </p>
            )}

            <div className="mt-2.5 flex flex-wrap items-start gap-2">
              {/*
                Giving up your own admin is the one change on this screen you
                cannot undo yourself, so it is the one that does not happen on
                the press. It reads like the button beside it and goes to a
                screen that says what is lost and who can give it back.
              */}
              {person.id === me.id && person.role === "admin" ? (
                <Link
                  href="/more/people/step-down"
                  className="flex h-11 items-center justify-center rounded-[10px] border-[1.5px] border-ink bg-surface px-4 text-[15px] font-semibold"
                >
                  Make a pilot
                </Link>
              ) : (
                <InlineAction
                  action={setRole}
                  tone="outline"
                  label={person.role === "admin" ? "Make a pilot" : "Make an admin"}
                  fields={{
                    id: person.id,
                    role: person.role === "admin" ? "pilot" : "admin",
                  }}
                />
              )}

              {person.id !== me.id && (
                <InlineAction
                  action={setActive}
                  tone="outline"
                  label={person.is_active ? "Retire" : "Bring back"}
                  fields={{
                    id: person.id,
                    is_active: person.is_active ? "false" : "true",
                  }}
                />
              )}
            </div>
          </div>
        ))}
      </main>
    </>
  );
}
