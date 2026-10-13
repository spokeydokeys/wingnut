"use client";

import dynamic from "next/dynamic";
import type { ReactNode } from "react";
import { useActionState, useRef, useState } from "react";

import { createPlace, setFlightPlace } from "@/app/places/actions";
import { Chip } from "@/components/chip";
import { FIELD } from "@/components/field";
import { PlaceFields } from "@/components/place-fields";
import { formatDistance } from "@/lib/format";
import { KIND_LABEL, type PlaceKind } from "@/lib/place-kind";
import { useOnline } from "@/lib/use-online";

/**
 * Loaded only in the browser, and only once `useOnline` says there is a
 * network. `ssr: false` is not an optimisation here: Leaflet touches `window`
 * while it loads, so rendering it on the server would throw.
 */
const PlaceMap = dynamic(() => import("./place-map").then((module) => module.PlaceMap), {
  ssr: false,
  loading: () => <div className="h-44 w-full animate-pulse bg-hairline" />,
});

type PlaceRow = { id: string; name: string; kind: PlaceKind };
type NearRow = PlaceRow & { distance_m: number };
type UsedRow = PlaceRow & { times_used: number };

/**
 * "Where did you land?" -- SPEC.md 4.6, from the Place wireframe.
 *
 * List-first by design. Every candidate the pilot is likely to want is
 * rendered on the server before this mounts, so the screen is usable with no
 * network at all; the map is layered on top when there happens to be one. That
 * is the shape the owner asked for, and it is also the right one for a float
 * plane, which lands in the places with the worst coverage.
 */
export function PlacePicker({
  flightId,
  which,
  currentPlaceId,
  fix,
  recent,
  near,
  all,
}: {
  flightId: string;
  which: "start" | "end";
  currentPlaceId: string | null;
  fix: { lat: number; lon: number; accuracyM: number | null } | null;
  recent: UsedRow[];
  near: NearRow[];
  all: PlaceRow[];
}) {
  const online = useOnline();

  const [selected, setSelected] = useState(currentPlaceId);
  const [query, setQuery] = useState("");
  const [pin, setPin] = useState(fix ? { lat: fix.lat, lon: fix.lon } : null);
  const [nearby, setNearby] = useState(near);
  const [staleDistances, setStaleDistances] = useState(false);

  // The new-place coordinates, as typed. Separate from `pin` because they are
  // text until they are a number -- half of "-123." is not a longitude -- and
  // because with no fix at all there is no pin but there is still a form.
  const [latText, setLatText] = useState(fix ? String(fix.lat) : "");
  const [lonText, setLonText] = useState(fix ? String(fix.lon) : "");

  const [chooseState, choose, choosing] = useActionState(setFlightPlace, null);
  const [createState, create, creating] = useActionState(createPlace, null);

  // Only the answer to the most recent drag may win. Dragging twice quickly
  // starts two requests and they can finish in either order.
  const latestRequest = useRef(0);

  const movePin = async (lat: number, lon: number) => {
    setPin({ lat, lon });
    setLatText(lat.toFixed(6));
    setLonText(lon.toFixed(6));

    const request = ++latestRequest.current;
    try {
      const response = await fetch(
        `/api/places/nearby?lat=${encodeURIComponent(lat)}&lon=${encodeURIComponent(lon)}`,
      );
      if (!response.ok) throw new Error(String(response.status));
      const body: { places?: NearRow[] } = await response.json();
      if (request !== latestRequest.current) return;
      setNearby(body.places ?? []);
      setStaleDistances(false);
    } catch {
      // The network went away mid-drag. The list stays, because a short list of
      // real places is still the most useful thing on the screen -- but the
      // distances now belong to where the pin used to be, and saying so is
      // cheaper than pretending.
      if (request === latestRequest.current) setStaleDistances(true);
    }
  };

  const needle = query.trim().toLowerCase();
  const matches =
    needle === "" ? [] : all.filter((place) => place.name.toLowerCase().includes(needle));

  return (
    <>
      <div className="flex min-h-0 flex-1 flex-col gap-2.5 overflow-y-auto">
        {online && pin ? (
          <div className="flex-none overflow-hidden rounded-[14px] border border-line">
            <PlaceMap lat={pin.lat} lon={pin.lon} fix={fix} onMove={movePin} />
          </div>
        ) : (
          // Not an error state and not styled like one. Offline, or with no fix
          // to centre on, the lists below are the screen -- the map was only
          // ever a way of reading them.
          <p className="flex-none rounded-[14px] border border-line bg-surface px-3.5 py-3 text-[13px] text-muted">
            {pin
              ? "No map while offline. Pick from the list, or save this spot by name."
              : "No GPS fix for this end of the flight. Pick from the list below."}
          </p>
        )}

        <div className="flex-none">
          <label htmlFor="place-search" className="field-label mb-1.5 block">
            Search places
          </label>
          <input
            id="place-search"
            type="search"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Airports, bays, lakes, saved docks"
            className={FIELD}
          />
        </div>

        {needle !== "" ? (
          <Section title={`${matches.length} match${matches.length === 1 ? "" : "es"}`}>
            {matches.map((place) => (
              <Row
                key={place.id}
                place={place}
                caption="Saved place"
                selected={selected === place.id}
                onSelect={setSelected}
              />
            ))}
            {matches.length === 0 && (
              <p className="text-[13px] text-muted">
                Nothing saved by that name yet. Save it below.
              </p>
            )}
          </Section>
        ) : (
          <>
            {recent.length > 0 && (
              <Section title="Recent">
                {recent.map((place) => (
                  <Row
                    key={place.id}
                    place={place}
                    caption={timesUsed(place.times_used)}
                    selected={selected === place.id}
                    onSelect={setSelected}
                  />
                ))}
              </Section>
            )}

            {nearby.length > 0 && (
              <Section
                title={fix ? "Near your GPS fix" : "Near the pin"}
                note={staleDistances ? "Distances are from the pin's last position." : undefined}
              >
                {nearby.map((place) => (
                  <Row
                    key={place.id}
                    place={place}
                    caption={formatDistance(Number(place.distance_m))}
                    selected={selected === place.id}
                    onSelect={setSelected}
                  />
                ))}
              </Section>
            )}
          </>
        )}

        <details className="flex-none rounded-[14px] border border-line bg-surface px-3.5 py-3">
          <summary className="cursor-pointer text-[15px] font-semibold">
            Not on the list? Save this spot
          </summary>

          {/*
            Its own form, so saving a place and naming the flight's end are one
            submission. `createPlace` links the new place to this flight itself
            -- the pilot does not come back here to tap what they just typed.
          */}
          <form action={create} className="mt-3 flex flex-col gap-3">
            <input type="hidden" name="flight_id" value={flightId} />
            <input type="hidden" name="which" value={which} />

            <PlaceFields
              lat={latText}
              lon={lonText}
              onLat={setLatText}
              onLon={setLonText}
              hint="Filled in from your GPS fix, and from the pin whenever you drag it."
            />

            {createState?.error && <Alert>{createState.error}</Alert>}

            <button
              type="submit"
              disabled={creating}
              className="flex h-12 items-center justify-center rounded-[10px] border border-ink text-base font-semibold disabled:opacity-60"
            >
              {creating ? "Saving…" : "Save place and use it"}
            </button>
          </form>
        </details>
      </div>

      {chooseState?.error && <Alert>{chooseState.error}</Alert>}

      <form action={choose} className="flex-none">
        <input type="hidden" name="flight_id" value={flightId} />
        <input type="hidden" name="which" value={which} />
        <input type="hidden" name="place_id" value={selected ?? ""} />
        <button
          type="submit"
          disabled={choosing || selected === null}
          className="flex h-14 w-full items-center justify-center rounded-[14px] bg-accent text-lg font-semibold text-white disabled:opacity-60"
        >
          {choosing ? "Saving…" : "Use this place"}
        </button>
      </form>
    </>
  );
}

/** `Used on 3 flights` -- this pilot's own count, which is what ranks the list. */
function timesUsed(count: number): string {
  if (count === 0) return "Saved place";
  return count === 1 ? "Used on 1 flight" : `Used on ${count} flights`;
}

function Section({
  title,
  note,
  children,
}: {
  title: string;
  note?: string;
  children: ReactNode;
}) {
  return (
    <div className="flex flex-none flex-col gap-2.5">
      <div className="field-label">{title}</div>
      {note && <p className="-mt-1.5 text-[13px] text-muted">{note}</p>}
      {children}
    </div>
  );
}

function Row({
  place,
  caption,
  selected,
  onSelect,
}: {
  place: PlaceRow;
  caption: string;
  selected: boolean;
  onSelect: (id: string) => void;
}) {
  return (
    <button
      type="button"
      aria-pressed={selected}
      onClick={() => onSelect(place.id)}
      className={`flex min-h-14 w-full items-center gap-3 rounded-xl bg-surface px-3 py-1.5 text-left ${
        selected ? "border-2 border-ink" : "border border-line"
      }`}
    >
      <span
        aria-hidden="true"
        className={`flex size-[18px] flex-none items-center justify-center rounded-full border-2 ${
          selected ? "border-ink" : "border-field"
        }`}
      >
        {selected && <span className="size-2 rounded-full bg-ink" />}
      </span>
      <span className="flex-1">
        <span className="block text-[15px] font-semibold">{place.name}</span>
        <span className="block text-[13px] text-muted">{caption}</span>
      </span>
      <Chip tone="neutral">{KIND_LABEL[place.kind]}</Chip>
    </button>
  );
}

function Alert({ children }: { children: ReactNode }) {
  return (
    <p
      role="alert"
      className="flex-none rounded-[10px] border border-snag-line bg-snag px-3 py-2.5 text-[13px] font-medium text-snag-text"
    >
      {children}
    </p>
  );
}
