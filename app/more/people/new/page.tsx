import { addPerson } from "@/app/more/actions";
import { ActionForm } from "@/components/action-form";
import { BackHeader } from "@/components/back-header";
import { FIELD } from "@/components/field";
import { requireAdmin } from "@/lib/dal";

export const dynamic = "force-dynamic";

/**
 * Add somebody to the roster. Two fields, because there are only two facts.
 *
 * The email is the credential: there is no password to set and no invitation
 * to generate, so adding a person is finished the moment they sign in at that
 * address themselves. Nothing is sent from here -- the app has no reason to be
 * a mail client when the sign-in page already sends the only message that
 * matters.
 */
export default async function NewPerson() {
  await requireAdmin();

  return (
    <>
      <BackHeader
        href="/more/people"
        label="People"
        title="Add a person"
        subtitle="They sign in at this address. Nothing is sent from here."
      />

      <main className="flex min-h-0 flex-1 flex-col overflow-y-auto px-4 pt-3.5 pb-4">
        <ActionForm action={addPerson} submitLabel="Add to the roster">
          <div>
            <label htmlFor="full_name" className="field-label mb-1.5 block">
              Name
            </label>
            <input
              id="full_name"
              name="full_name"
              type="text"
              required
              autoComplete="off"
              className={FIELD}
            />
            <p className="mt-1.5 text-[13px] text-muted">
              As it should read on a booking and on their invoices.
            </p>
          </div>

          <div>
            <label htmlFor="email" className="field-label mb-1.5 block">
              Email
            </label>
            <input
              id="email"
              name="email"
              type="email"
              required
              autoComplete="off"
              autoCapitalize="none"
              spellCheck={false}
              className={FIELD}
            />
            <p className="mt-1.5 text-[13px] text-muted">
              This is how they get in, so it has to be exactly right. A sign-in
              link sent to any other address will not find them.
            </p>
          </div>

          <p className="rounded-[10px] border border-line bg-surface px-3 py-2.5 text-[13px] text-muted">
            They join as a pilot: they can fly, book, file receipts and see
            their own bills. Admin is given afterwards, on the People screen.
          </p>
        </ActionForm>
      </main>
    </>
  );
}
