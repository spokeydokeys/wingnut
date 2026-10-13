import type { Database } from "./database.types";

export type PlaceKind = Database["public"]["Enums"]["place_kind"];

/**
 * What a place's kind is called on screen.
 *
 * Short on purpose: these render as the pill on the right of a list row, where
 * the wireframe allows about eight characters. "Water aerodrome" is the legal
 * name and will not fit, and the pill sits beside the place's own name, which
 * is where the detail belongs.
 *
 * Not in lib/places.ts because that module is server-only and the place picker
 * needs these in the browser.
 */
export const KIND_LABEL: Record<PlaceKind, string> = {
  airport: "Airport",
  water_aerodrome: "Water",
  heliport: "Heliport",
  bay: "Bay",
  lake: "Lake",
  dock: "Dock",
  other: "Place",
};

/** The kinds in the order they are offered, commonest first for this aeroplane. */
export const KIND_CHOICES: PlaceKind[] = [
  "dock",
  "bay",
  "lake",
  "water_aerodrome",
  "airport",
  "heliport",
  "other",
];
