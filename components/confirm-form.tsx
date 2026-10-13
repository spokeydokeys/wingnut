"use client";

import { useState, useTransition } from "react";

import { cancelFlight, saveFlight } from "@/app/flight/actions";
import { formatDuration, formatHours, nearestTenth, roundUpTenth } from "@/lib/format";
import { fromInputValue, toInputValue } from "@/lib/time";

/**
 * The editable half of the Confirm screen.
 *
 * Client-side because the hours have to move as the times are typed: a pilot
 * correcting a forgotten Stop needs to see what the correction costs before
 * saving it. The figures shown here are advisory -- `flight_compute_hours`
 * recalculates them in the database on save, so what gets billed does not
 * depend on this file being right.
 *
 * The wireframe's separate Date field is folded into the two datetime inputs.
 * A date plus two times cannot express a flight that lands after midnight,
 * which is exactly the forgot-to-stop case this screen is for.
 */
export function ConfirmForm({
  flightId,
  startAt,
  endAt,
  pilotMemberId,
  pilots,
  tachFactor,
  actualTachHours,
  notes,
  canChangePilot,
}: {
  flightId: string;
  startAt: string;
  endAt: string;
  pilotMemberId: string;
  pilots: { id: string; full_name: string }[];
  tachFactor: number;
  actualTachHours: string;
  notes: string;
  canChangePilot: boolean;
}) {
  const [start, setStart] = useState(() => toInputValue(startAt));
  const [end, setEnd] = useState(() => toInputValue(endAt));
  const [pilot, setPilot] = useState(pilotMemberId);
  const [tach, setTach] = useState(actualTachHours);
  const [note, setNote] = useState(notes);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const startDate = fromInputValue(start);
  const endDate = fromInputValue(end);
  const durationMs =
    startDate && endDate ? endDate.valueOf() - startDate.valueOf() : null;
  const valid = durationMs !== null && durationMs > 0;
  const hours = valid ? durationMs / 3_600_000 : null;

  const submit = () => {
    setError(null);
    startTransition(async () => {
      const result = await saveFlight({
        flightId,
        startAt: startDate!.toISOString(),
        endAt: endDate!.toISOString(),
        pilotMemberId: pilot,
        actualTachHours: tach,
        notes: note,
      });
      // On success the action redirects and never returns, so anything here is
      // a refusal worth putting in front of the pilot.
      if (result?.error) setError(result.error);
    });
  };

  const field =
    "h-12 w-full rounded-[10px] border border-field bg-surface px-3 text-base font-medium text-ink";

  return (
    <>
      <div>
        <label htmlFor="pilot" className="field-label mb-1.5 block">
          Pilot
        </label>
        {canChangePilot ? (
          <select
            id="pilot"
            value={pilot}
            onChange={(event) => setPilot(event.target.value)}
            className={field}
          >
            {pilots.map((choice) => (
              <option key={choice.id} value={choice.id}>
                {choice.full_name}
              </option>
            ))}
          </select>
        ) : (
          // Naming another pilot moves the cost of the flight onto their bill,
          // so for everyone but an admin this is a fact, not a field.
          <div className={`${field} flex items-center text-muted`}>
            {pilots.find((choice) => choice.id === pilot)?.full_name ?? "You"}
          </div>
        )}
      </div>

      {/*
        Stacked, not the wireframe's side-by-side pair. A datetime-local input
        renders a full date and a time, and two of them do not fit across a
        phone -- the second one was being cut off at the screen edge.
      */}
      <div className="flex flex-col gap-3">
        <div className="flex-1">
          <label htmlFor="start" className="field-label mb-1.5 block">
            Start
          </label>
          <input
            id="start"
            type="datetime-local"
            value={start}
            onChange={(event) => setStart(event.target.value)}
            className={`${field} numeric`}
          />
        </div>
        <div className="flex-1">
          <label htmlFor="end" className="field-label mb-1.5 block">
            End
          </label>
          <input
            id="end"
            type="datetime-local"
            value={end}
            onChange={(event) => setEnd(event.target.value)}
            className={`${field} numeric`}
          />
        </div>
      </div>
      <p className="-mt-1.5 text-[13px] text-muted">
        Forgot to stop the clock? Set the real end time.
      </p>

      <div className="flex rounded-xl border border-ink bg-surface px-3.5 py-3">
        <div className="flex-1">
          <div className="field-label">Billed to you</div>
          <div className="numeric text-[28px]">
            {hours === null ? "– hr" : formatHours(roundUpTenth(hours))}
          </div>
          <div className="text-[13px] text-muted">
            {durationMs === null || durationMs <= 0
              ? "Check the times"
              : `${formatDuration(durationMs)} flight time`}
          </div>
        </div>
        <div className="mx-3.5 w-px bg-line" />
        <div className="flex-1">
          <div className="field-label">Est. tach</div>
          <div className="numeric text-[28px]">
            {hours === null ? "– hr" : formatHours(nearestTenth(hours / tachFactor))}
          </div>
          <div className="text-[13px] text-muted">Estimate only</div>
        </div>
      </div>

      <div>
        <label htmlFor="tach" className="field-label mb-1.5 block">
          Actual tach reading (optional)
        </label>
        <input
          id="tach"
          type="number"
          inputMode="decimal"
          step="0.01"
          min="0"
          value={tach}
          onChange={(event) => setTach(event.target.value)}
          placeholder="Enter if you looked at it"
          className={field}
        />
      </div>

      <div>
        <label htmlFor="notes" className="field-label mb-1.5 block">
          Notes (optional)
        </label>
        <input
          id="notes"
          type="text"
          value={note}
          onChange={(event) => setNote(event.target.value)}
          placeholder="Where to, anything worth remembering"
          className={field}
        />
      </div>

      {error && (
        <p
          role="alert"
          className="rounded-[10px] border border-snag-line bg-snag px-3 py-2.5 text-[13px] font-medium text-snag-text"
        >
          {error}
        </p>
      )}

      <div className="flex-1" />

      <button
        type="button"
        onClick={submit}
        disabled={pending || !valid}
        className="flex h-14 items-center justify-center rounded-[14px] bg-accent text-lg font-semibold text-white disabled:opacity-60"
      >
        {pending ? "Saving…" : "Save flight"}
      </button>

      <form action={cancelFlight.bind(null, flightId)} className="flex justify-center">
        <button
          type="submit"
          className="flex min-h-11 items-center justify-center text-[15px] font-medium text-muted underline"
        >
          Discard
        </button>
      </form>
    </>
  );
}
