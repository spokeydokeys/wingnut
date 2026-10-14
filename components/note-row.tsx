import type { AircraftNote } from "@/lib/aircraft";
import { formatHours } from "@/lib/format";
import { formatDate } from "@/lib/time";

/**
 * One line of the running log, shared by the Aircraft tab's last five and the
 * full history at /aircraft/log.
 *
 * Shared rather than written twice because the two lists are the same list --
 * if the tab ever showed a note differently from the log, the question would be
 * which of them was the record.
 */
export function NoteRow({ note }: { note: AircraftNote }) {
  return (
    <div className="py-3">
      {/* whitespace-pre-line so a note written as two lines stays two. */}
      <p className="text-[15px] whitespace-pre-line">{note.body}</p>
      <p className="mt-0.5 text-[13px] text-muted">
        {formatDate(note.noted_on)}
        {note.author && ` · ${note.author.full_name}`}
        {/*
          The tach is shown because it is the one part of a note that changes
          what the rest of the Aircraft tab says: it is mirrored into
          tach_reading, so the maintenance due-dates are measured from it.
        */}
        {note.tach !== null && (
          <>
            {" · "}
            <span className="numeric">{formatHours(Number(note.tach))}</span>
          </>
        )}
      </p>
    </div>
  );
}
