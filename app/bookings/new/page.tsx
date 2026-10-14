import { redirect } from "next/navigation";

import { createBooking } from "@/app/bookings/actions";
import { ActionForm } from "@/components/action-form";
import { BackHeader } from "@/components/back-header";
import { FIELD } from "@/components/field";
import { defaultSlot } from "@/lib/bookings";
import { requireMember } from "@/lib/dal";
import { getAircraft, getPilotChoices } from "@/lib/flights";

export const dynamic = "force-dynamic";

/**
 * Hold the aeroplane for a slot.
 *
 * Two datetime fields rather than a date plus two times, for the same reason
 * the Confirm screen folded them together: a date and two times cannot say
 * "Friday evening until Saturday lunchtime", and a weekend away is the one
 * booking worth being able to make.
 *
 * Pre-filled with the next whole hour and three hours of it, because the most
 * common booking is "I am going flying shortly" and an empty datetime input is
 * the most tedious control on a phone. Both are still fields, so nothing is
 * assumed about the slot anybody actually wants.
 */
export default async function NewBooking() {
  const member = await requireMember();

  const aircraft = await getAircraft();
  if (!aircraft) redirect("/no-access");

  const slot = defaultSlot();

  // Only an admin may name somebody else, which is what `booking_insert_own`
  // allows. For everybody else there is no choice to make, so no control.
  const pilots = member.role === "admin" ? await getPilotChoices() : [];

  return (
    <>
      <BackHeader
        href="/bookings"
        label="Bookings"
        title="Book the aeroplane"
        subtitle="Nobody else can take a slot you are holding."
      />

      <main className="flex min-h-0 flex-1 flex-col overflow-y-auto px-4 pt-3.5 pb-4">
        <ActionForm action={createBooking} submitLabel="Book it">
          {pilots.length > 0 && (
            <div>
              <label htmlFor="pilot_member_id" className="field-label mb-1.5 block">
                Who is flying
              </label>
              <select
                id="pilot_member_id"
                name="pilot_member_id"
                defaultValue={member.id}
                className={FIELD}
              >
                {pilots.map((pilot) => (
                  <option key={pilot.id} value={pilot.id}>
                    {pilot.full_name}
                  </option>
                ))}
              </select>
            </div>
          )}

          <div>
            <label htmlFor="start_at" className="field-label mb-1.5 block">
              From
            </label>
            <input
              id="start_at"
              name="start_at"
              type="datetime-local"
              required
              defaultValue={slot.start}
              className={`${FIELD} numeric`}
            />
          </div>

          <div>
            <label htmlFor="end_at" className="field-label mb-1.5 block">
              Until
            </label>
            <input
              id="end_at"
              name="end_at"
              type="datetime-local"
              required
              defaultValue={slot.end}
              className={`${FIELD} numeric`}
            />
            <p className="mt-1.5 text-[13px] text-muted">
              Handing over at noon? End at 12:00 and the next booking can start
              at 12:00 — that is not a clash.
            </p>
          </div>

          <div>
            <label htmlFor="note" className="field-label mb-1.5 block">
              What for (optional)
            </label>
            <input
              id="note"
              name="note"
              type="text"
              placeholder="Ganges for lunch, back mid afternoon"
              className={FIELD}
            />
            <p className="mt-1.5 text-[13px] text-muted">
              For the other owner deciding whether it is worth asking for the
              slot.
            </p>
          </div>
        </ActionForm>
      </main>
    </>
  );
}
