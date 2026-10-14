import { FIELD } from "@/components/field";

/**
 * "Bought from", with the places this member buys from offered as you type.
 *
 * A native `<datalist>` rather than a hand-built dropdown. It is a free text
 * field first and a list second -- a pilot fuels somewhere new often enough
 * that a picker which refuses an unknown name would be wrong -- and the
 * browser's own suggestion UI is the one that behaves properly above a phone
 * keyboard, works with no JavaScript, and cannot get stuck open offline.
 *
 * The order the options are written in is the order they are offered in, so
 * the ranking done by `getVendorSuggestions` survives into the dropdown.
 *
 * `autoComplete="off"` is still right: it turns off the browser's own guesses,
 * harvested from every other form on the web, in favour of this list.
 */
export function VendorField({
  vendors,
  defaultValue,
}: {
  vendors: string[];
  defaultValue?: string;
}) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className="field-label">Bought from</span>
      <input
        name="vendor"
        required
        list={vendors.length > 0 ? "vendor-suggestions" : undefined}
        autoComplete="off"
        defaultValue={defaultValue}
        placeholder="Esso Nanaimo"
        className={FIELD}
      />
      {vendors.length > 0 && (
        <datalist id="vendor-suggestions">
          {vendors.map((vendor) => (
            <option key={vendor} value={vendor} />
          ))}
        </datalist>
      )}
    </label>
  );
}
