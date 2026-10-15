"use client";

import { useState } from "react";

import { FIELD } from "./field";

export type Holder = {
  id: string;
  name: string;
  shares: number;
  note: string | null;
};

/**
 * One share box per person, and a running total under them.
 *
 * The total has to add up to the company's share count exactly, and the
 * database refuses it if it does not -- but finding out at the end of the form
 * that four numbers come to 1150 means working out by hand which one is wrong.
 * The tally says it while the typing is happening, which is the only moment the
 * arithmetic is useful.
 *
 * It is advice, not enforcement. The field is still a plain number input and
 * `record_ownership_period` still refuses a bad total, because a tally that is
 * the only thing standing between a typo and the billing would be a rule that
 * only the browser obeys.
 */
export function ShareTally({
  holders,
  total,
}: {
  holders: Holder[];
  total: number;
}) {
  const [held, setHeld] = useState<Record<string, string>>(() =>
    Object.fromEntries(holders.map((h) => [h.id, String(h.shares)])),
  );

  // An empty box reads as nothing held, which is what it looks like. A box
  // mid-typing ("4e") is not a number and is left out of the sum rather than
  // making the whole tally say NaN.
  const sum = holders.reduce((running, holder) => {
    const value = Number(held[holder.id]);
    return running + (Number.isFinite(value) ? value : 0);
  }, 0);

  const difference = total - sum;

  return (
    <>
      {holders.map((holder) => (
        <div key={holder.id}>
          <label htmlFor={`shares.${holder.id}`} className="field-label mb-1.5 block">
            {holder.name}
          </label>
          <input
            id={`shares.${holder.id}`}
            name={`shares.${holder.id}`}
            type="number"
            inputMode="numeric"
            min={0}
            step={1}
            required
            value={held[holder.id] ?? ""}
            onChange={(event) =>
              setHeld({ ...held, [holder.id]: event.target.value })
            }
            className={FIELD}
          />
          {holder.note && (
            <p className="mt-1.5 text-[13px] text-muted">{holder.note}</p>
          )}
        </div>
      ))}

      <p
        aria-live="polite"
        className={`rounded-[10px] border px-3 py-2.5 text-[15px] font-medium ${
          difference === 0
            ? "border-line bg-surface text-muted"
            : "border-caution-line bg-caution text-caution-text"
        }`}
      >
        {sum} of {total} shares
        {difference === 0
          ? " · that adds up"
          : difference > 0
            ? ` · ${difference} still to give out`
            : ` · ${-difference} too many`}
      </p>
    </>
  );
}
