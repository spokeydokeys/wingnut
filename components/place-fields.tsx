"use client";

import { FIELD } from "@/components/field";
import { KIND_CHOICES, KIND_LABEL } from "@/lib/place-kind";

/**
 * The four fields that make a place: name, kind, latitude, longitude.
 *
 * Shared by the Set place screen and the saved-places manager because both
 * post to the same `createPlace` action. The coordinates are controlled from
 * outside so that the picker's map can write into them while the manager,
 * which has no map, simply lets them be typed.
 */
export function PlaceFields({
  lat,
  lon,
  onLat,
  onLon,
  hint,
}: {
  lat: string;
  lon: string;
  onLat: (value: string) => void;
  onLon: (value: string) => void;
  hint: string;
}) {
  return (
    <>
      <div>
        <label htmlFor="place-name" className="field-label mb-1.5 block">
          Name
        </label>
        <input
          id="place-name"
          name="name"
          type="text"
          required
          placeholder="Tod Inlet dock"
          className={FIELD}
        />
      </div>

      <div>
        <label htmlFor="place-kind" className="field-label mb-1.5 block">
          Kind
        </label>
        <select id="place-kind" name="kind" defaultValue="dock" className={FIELD}>
          {KIND_CHOICES.map((kind) => (
            <option key={kind} value={kind}>
              {KIND_LABEL[kind]}
            </option>
          ))}
        </select>
      </div>

      <div className="flex gap-3">
        <div className="flex-1">
          <label htmlFor="place-lat" className="field-label mb-1.5 block">
            Latitude
          </label>
          <input
            id="place-lat"
            name="lat"
            type="number"
            inputMode="decimal"
            step="0.000001"
            required
            value={lat}
            onChange={(event) => onLat(event.target.value)}
            className={`${FIELD} numeric`}
          />
        </div>
        <div className="flex-1">
          <label htmlFor="place-lon" className="field-label mb-1.5 block">
            Longitude
          </label>
          <input
            id="place-lon"
            name="lon"
            type="number"
            inputMode="decimal"
            step="0.000001"
            required
            value={lon}
            onChange={(event) => onLon(event.target.value)}
            className={`${FIELD} numeric`}
          />
        </div>
      </div>

      <p className="text-[13px] text-muted">{hint}</p>
    </>
  );
}
