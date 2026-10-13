"use client";

import { useEffect, useState } from "react";

/**
 * Whether the browser thinks it has a network.
 *
 * Starts `false` and only becomes true in an effect, which is deliberate: the
 * server has no opinion about the client's connection, so rendering the
 * optimistic answer first would be a hydration mismatch. The cost is that an
 * online screen shows its offline form for one frame; the benefit is that the
 * offline screen is the one that always renders, which is the right way round
 * for an aeroplane.
 *
 * `navigator.onLine` is only ever a hint -- true means "an interface is up",
 * not "the internet answers" -- so nothing here may be load-bearing. It gates
 * the map, and the fetch that goes with the map handles its own failure.
 */
export function useOnline(): boolean {
  const [online, setOnline] = useState(false);

  useEffect(() => {
    const update = () => setOnline(navigator.onLine);
    update();
    window.addEventListener("online", update);
    window.addEventListener("offline", update);
    return () => {
      window.removeEventListener("online", update);
      window.removeEventListener("offline", update);
    };
  }, []);

  return online;
}
