"use client";

import { useActionState, useState } from "react";

import { createPlace, deletePlace, renamePlace } from "@/app/places/actions";
import { FIELD } from "@/components/field";
import { PlaceFields } from "@/components/place-fields";

/**
 * Rename or delete one saved place, in the More tab's manager.
 *
 * Renaming is the operation this screen is really for. A place that any flight
 * has ever named cannot be deleted -- `place_guard_in_use` refuses -- so when
 * "Dock" turns out to be "Tod Inlet dock", renaming is the only thing that
 * fixes the journey log, and it fixes it everywhere at once.
 */
export function PlaceEditor({ placeId, name }: { placeId: string; name: string }) {
  const [renameState, rename, renaming] = useActionState(renamePlace, null);
  const [deleteState, remove, deleting] = useActionState(deletePlace, null);

  return (
    <details className="mt-2.5">
      <summary className="cursor-pointer text-[15px] font-medium underline">Edit</summary>

      <form action={rename} className="mt-2.5 flex flex-col gap-2.5">
        <input type="hidden" name="place_id" value={placeId} />
        <label htmlFor={`name-${placeId}`} className="field-label block">
          Name
        </label>
        <input
          id={`name-${placeId}`}
          name="name"
          type="text"
          required
          defaultValue={name}
          className={FIELD}
        />
        {renameState?.error && <Alert>{renameState.error}</Alert>}
        <button
          type="submit"
          disabled={renaming}
          className="flex h-11 items-center justify-center rounded-[10px] border-[1.5px] border-ink bg-surface text-[15px] font-semibold disabled:opacity-60"
        >
          {renaming ? "Saving…" : "Save name"}
        </button>
      </form>

      <form action={remove} className="mt-2.5">
        <input type="hidden" name="place_id" value={placeId} />
        {deleteState?.error && <Alert>{deleteState.error}</Alert>}
        <button
          type="submit"
          disabled={deleting}
          className="mt-2.5 flex min-h-11 items-center text-[15px] font-medium text-muted underline disabled:opacity-60"
        >
          {deleting ? "Deleting…" : "Delete this place"}
        </button>
      </form>
    </details>
  );
}

/**
 * Save a place nobody has flown to yet.
 *
 * The Set place screen can create a place too, from a GPS fix, which is how it
 * will usually happen. This is for the other direction: reading a chart at the
 * kitchen table the night before.
 */
export function NewPlaceForm() {
  const [state, create, creating] = useActionState(createPlace, null);
  const [lat, setLat] = useState("");
  const [lon, setLon] = useState("");

  return (
    <details className="rounded-[14px] border border-line bg-surface px-3.5 py-3">
      <summary className="cursor-pointer text-[15px] font-semibold">Save a new place</summary>

      {/* No flight_id, so `createPlace` saves the place and comes back here. */}
      <form action={create} className="mt-3 flex flex-col gap-3">
        <PlaceFields
          lat={lat}
          lon={lon}
          onLat={setLat}
          onLon={setLon}
          hint="Decimal degrees. South and west are negative, so Victoria is 48.42, -123.39."
        />

        {state?.error && <Alert>{state.error}</Alert>}

        <button
          type="submit"
          disabled={creating}
          className="flex h-12 items-center justify-center rounded-[10px] bg-accent text-base font-semibold text-white disabled:opacity-60"
        >
          {creating ? "Saving…" : "Save place"}
        </button>
      </form>
    </details>
  );
}

function Alert({ children }: { children: string }) {
  return (
    <p
      role="alert"
      className="rounded-[10px] border border-snag-line bg-snag px-3 py-2.5 text-[13px] font-medium text-snag-text"
    >
      {children}
    </p>
  );
}
