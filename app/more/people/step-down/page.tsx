import Link from "next/link";

import { stepDownAsAdmin } from "@/app/more/actions";
import { ActionForm } from "@/components/action-form";
import { BackHeader } from "@/components/back-header";
import { requireAdmin } from "@/lib/dal";
import { getPeople } from "@/lib/people";

export const dynamic = "force-dynamic";

/**
 * The one screen on the People flow whose whole job is to be read.
 *
 * Every other button there is undone by the button that replaces it: retire
 * somebody and the same row offers Bring back. Giving up your own admin is the
 * exception -- only an admin may hand out admin, so the moment it is done the
 * person who did it cannot undo it. That is worth a screen rather than a press.
 *
 * It names the people who could give it back, because "ask another admin" is
 * only useful advice if you know who they are, and because seeing the list is
 * how somebody notices there is nobody on it.
 */
export default async function StepDown() {
  const me = await requireAdmin();
  const people = await getPeople();

  const others = people.filter(
    (person) => person.id !== me.id && person.is_active && person.role === "admin",
  );

  return (
    <>
      <BackHeader
        href="/more/people"
        label="People"
        title="Step down as admin"
        subtitle="You keep flying. You stop being able to run the company side."
      />

      <main className="flex min-h-0 flex-1 flex-col overflow-y-auto px-4 pt-3.5 pb-4">
        <ActionForm
          action={stepDownAsAdmin}
          submitLabel="Step down as admin"
          footer={
            <Link
              href="/more/people"
              className="flex h-11 flex-none items-center justify-center text-[15px] font-semibold text-muted"
            >
              Cancel
            </Link>
          }
        >
          <p className="text-[15px]">
            You go back to being a pilot. You can still fly, book the aeroplane,
            file receipts and see your own bills.
          </p>

          <div className="rounded-[14px] border border-line bg-surface px-3.5 py-3">
            <div className="field-label mb-1.5">You will no longer be able to</div>
            <ul className="flex list-disc flex-col gap-1 pl-5 text-[15px]">
              <li>close a month, or issue and send invoices</li>
              <li>record a payment against somebody&rsquo;s bill</li>
              <li>change what the aeroplane costs to fly</li>
              <li>add, retire or promote anybody, including yourself</li>
            </ul>
          </div>

          {/*
            An admin who is the last one will be refused by
            member_keeps_an_admin when they press the button, which is the right
            place for the rule. Saying it here as well means they do not have to
            press a button to find out.
          */}
          <p className="rounded-[10px] border border-caution-line bg-caution px-3 py-2.5 text-[13px] font-medium text-caution-text">
            {others.length === 0
              ? "You are the only admin. This will be refused until somebody else is made one, because a roster with no admins cannot be fixed from inside the app."
              : others.length === 1
                ? `Only an admin can give admin back, so undoing this means asking ${others[0].full_name}.`
                : `Only an admin can give admin back, so undoing this means asking one of: ${others
                    .map((person) => person.full_name)
                    .join(", ")}.`}
          </p>
        </ActionForm>
      </main>
    </>
  );
}
