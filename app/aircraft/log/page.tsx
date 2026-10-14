import Link from "next/link";
import { redirect } from "next/navigation";

import { BackHeader } from "@/components/back-header";
import { NoteRow } from "@/components/note-row";
import { getAircraftNotes } from "@/lib/aircraft";
import { requireMember } from "@/lib/dal";
import { getAircraft } from "@/lib/flights";

export const dynamic = "force-dynamic";

/**
 * The whole running log, oldest note still there.
 *
 * No paging and no cap. The thing this screen is for is reading down the
 * column -- "how often has oil gone in this year?" -- and that question is not
 * answerable on a list that stops somewhere without saying so. One aeroplane
 * with a few owners writes tens of these a year, so the honest list is also the
 * cheap one; if that ever stops being true the fix is a year filter, not a
 * silent limit.
 */
export default async function AircraftLog() {
  await requireMember();

  const aircraft = await getAircraft();
  if (!aircraft) redirect("/no-access");

  const notes = await getAircraftNotes(aircraft.id);

  return (
    <>
      <BackHeader
        href="/aircraft"
        label="Aircraft"
        title="Log"
        subtitle="Everything done to the aeroplane that needed no decision from anyone."
        action={
          <Link
            href="/aircraft/note/new"
            className="flex h-11 items-center rounded-[10px] border-[1.5px] border-ink bg-surface px-4 text-[15px] font-semibold"
          >
            + Note
          </Link>
        }
      />

      <main className="flex min-h-0 flex-1 flex-col overflow-y-auto px-4 pt-3.5 pb-4">
        {notes.length === 0 ? (
          <p className="flex-none rounded-[14px] border border-line bg-surface px-3.5 py-3 text-[15px] text-muted">
            Nothing logged yet.
          </p>
        ) : (
          <div className="flex-none divide-y divide-hairline rounded-[14px] border border-line bg-surface px-3.5">
            {notes.map((note) => (
              <NoteRow key={note.id} note={note} />
            ))}
          </div>
        )}
      </main>
    </>
  );
}
