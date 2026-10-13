"use client";

import "leaflet/dist/leaflet.css";

import { useEffect, useRef } from "react";

/**
 * The draggable pin from the Place wireframe, on real tiles.
 *
 * Mounted only when the browser says it is online, and only ever through a
 * dynamic import -- see components/place-picker.tsx. That is the whole reason
 * this is a separate file: Leaflet is ~150 kB and reaches for `window` as it
 * loads, so it must not be in the bundle of a screen that has to work in a bay
 * with no signal.
 *
 * Raw Leaflet rather than react-leaflet. The pin is one marker with one event;
 * a wrapper would add a peer-dependency to keep in step with React for no gain.
 */
export function PlaceMap({
  lat,
  lon,
  fix,
  onMove,
}: {
  lat: number;
  lon: number;
  /** The GPS fix, drawn as a fixed ring so the pin can be judged against it. */
  fix: { lat: number; lon: number; accuracyM: number | null } | null;
  onMove: (lat: number, lon: number) => void;
}) {
  const container = useRef<HTMLDivElement | null>(null);

  // The map is built once and then owns the pin's position, so it reads these
  // through refs rather than from the dependency array. Putting `lat`/`lon` in
  // the deps would tear the map down and rebuild it on every drag, which would
  // throw away the zoom the pilot had just set.
  const start = useRef({ lat, lon, fix });
  const move = useRef(onMove);

  // Kept current in its own effect rather than assigned during render, which
  // React forbids. The map is built once and lives longer than any one
  // `onMove` closure, so it has to reach the latest one through here.
  useEffect(() => {
    move.current = onMove;
  }, [onMove]);

  useEffect(() => {
    const element = container.current;
    if (!element) return;

    let map: import("leaflet").Map | null = null;
    let cancelled = false;

    import("leaflet").then((L) => {
      if (cancelled || !container.current) return;

      const { lat: lat0, lon: lon0, fix: fix0 } = start.current;
      map = L.map(element, { zoomControl: false }).setView([lat0, lon0], 14);

      L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
        maxZoom: 19,
        // Required by the OSM tile usage policy, and the control is why the
        // card below is 176px of map plus the attribution strip.
        attribution: '&copy; <a href="https://openstreetmap.org/copyright">OpenStreetMap</a>',
      }).addTo(map);

      if (fix0) {
        // The accuracy circle, when the phone reported one. Drawn under the pin
        // so a drag inside it reads as "same spot, better named".
        if (fix0.accuracyM !== null) {
          L.circle([fix0.lat, fix0.lon], {
            radius: fix0.accuracyM,
            color: "#5b6676",
            weight: 1,
            dashArray: "4 4",
            fill: false,
          }).addTo(map);
        }
        L.circleMarker([fix0.lat, fix0.lon], {
          radius: 4,
          color: "#14213d",
          fillColor: "#14213d",
          fillOpacity: 1,
          weight: 0,
        })
          .addTo(map)
          .bindTooltip("Your GPS fix");
      }

      // A divIcon, not Leaflet's default marker: that one loads its artwork
      // from image files beside the stylesheet, and the paths it builds are
      // wrong once the CSS has been through a bundler.
      const marker = L.marker([lat0, lon0], {
        draggable: true,
        keyboard: true,
        alt: "Landing spot, drag to move",
        icon: L.divIcon({
          className: "",
          html:
            '<svg width="28" height="28" viewBox="0 0 24 24" aria-hidden="true">' +
            '<path d="M12 22s9-7.9 9-14a9 9 0 10-18 0c0 6.1 9 14 9 14z" fill="#c2410c"/>' +
            '<circle cx="12" cy="8" r="3" fill="#fff"/></svg>',
          iconSize: [28, 28],
          iconAnchor: [14, 28],
        }),
      }).addTo(map);

      marker.on("dragend", () => {
        const point = marker.getLatLng();
        move.current(point.lat, point.lng);
      });
    });

    return () => {
      cancelled = true;
      map?.remove();
    };
  }, []);

  return (
    <div
      ref={container}
      // Leaflet measures its container, so the height has to be real CSS and
      // not something the map sets for itself.
      className="h-44 w-full"
      role="application"
      aria-label="Map of your GPS fix with a pin you can drag to the landing spot"
    />
  );
}
