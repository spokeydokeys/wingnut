import { BackHeader } from "@/components/back-header";
import { Chip } from "@/components/chip";
import { NewPlaceForm, PlaceEditor } from "@/components/place-editor";
import { requireMember } from "@/lib/dal";
import { KIND_LABEL } from "@/lib/place-kind";
import { getPlaceUseCounts, getPlaces } from "@/lib/places";

export const dynamic = "force-dynamic";

/**
 * The saved-places manager. SPEC.md 3 puts this in the More tab.
 *
 * The owner chose saved places only -- no imported dataset -- so this list is
 * everything the app knows about where the aeroplane goes, and it grows as the
 * aeroplane goes places. The use count beside each row is every pilot's
 * flights, not the reader's: it is here to say what a rename would touch and
 * why a delete is going to be refused.
 */
export default async function SavedPlaces() {
  await requireMember();

  const [places, counts] = await Promise.all([getPlaces(), getPlaceUseCounts()]);

  return (
    <>
      <BackHeader
        href="/more"
        label="More"
        title="Saved places"
        subtitle="Every place the aeroplane has been named at. Renaming one fixes the journey log everywhere."
      />

      <main className="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto px-4 pt-3.5 pb-4">
        <NewPlaceForm />

        {places.length === 0 && (
          <p className="rounded-[14px] border border-line bg-surface p-3.5 text-[15px] text-muted">
            No places saved yet. The quickest way to add one is from the Confirm screen
            after a flight, where your GPS fix fills in the coordinates.
          </p>
        )}

        {places.map((place) => {
          const used = counts.get(place.id) ?? 0;

          return (
            <div
              key={place.id}
              className="rounded-[14px] border border-line bg-surface px-3.5 py-3"
            >
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <div className="text-base font-semibold">{place.name}</div>
                  <div className="text-[13px] text-muted">
                    {used === 0
                      ? "Not on any flight yet"
                      : `On ${used} flight${used === 1 ? "" : "s"}`}
                    {" · "}
                    <span className="numeric">
                      {Number(place.lat).toFixed(4)}, {Number(place.lon).toFixed(4)}
                    </span>
                  </div>
                </div>
                <Chip tone="neutral">{KIND_LABEL[place.kind]}</Chip>
              </div>

              <PlaceEditor placeId={place.id} name={place.name} />
            </div>
          );
        })}
      </main>
    </>
  );
}
