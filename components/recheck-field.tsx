"use client";

import { useState } from "react";

import { FIELD } from "@/components/field";

/**
 * When should this snag come back to my attention?
 *
 * One question with three shapes of answer, so one control decides and the
 * follow-up field appears only for the answer that needs one. A seep gets
 * looked at next time the cowling is off; "changed oil type, check again in
 * 10 hr" is the same question answered in tach hours; a date is for the thing
 * that has to be seen before the spring.
 *
 * This is the one field group on the snag screens that is interactive, and the
 * reason is that the alternative -- all three inputs on screen at once, with a
 * caption explaining that only one of them counts -- is worse on a phone than a
 * few lines of client state.
 */
export function RecheckField({
  items,
  itemId,
  tachHours,
  on,
}: {
  items: { id: string; name: string }[];
  itemId: string | null;
  tachHours: number | null;
  on: string | null;
}) {
  const [choice, setChoice] = useState(
    itemId !== null
      ? `item:${itemId}`
      : tachHours !== null
        ? "tach"
        : on !== null
          ? "date"
          : "none",
  );

  return (
    <div>
      <label htmlFor="recheck" className="field-label mb-1.5 block">
        Re-check
      </label>
      <select
        id="recheck"
        name="recheck"
        value={choice}
        onChange={(event) => setChoice(event.target.value)}
        className={FIELD}
      >
        <option value="none">Not needed</option>
        {/*
          The item names are left exactly as the maintenance programme spells
          them, which is why they sit under a heading instead of being folded
          into a sentence.
        */}
        {items.length > 0 && (
          <optgroup label="At the next…">
            {items.map((item) => (
              <option key={item.id} value={`item:${item.id}`}>
                {item.name}
              </option>
            ))}
          </optgroup>
        )}
        <optgroup label="Or on its own schedule">
          <option value="tach">After some tach hours</option>
          <option value="date">On a date</option>
        </optgroup>
      </select>

      {choice === "tach" && (
        <div className="mt-2.5">
          <label htmlFor="recheck_hours" className="field-label mb-1.5 block">
            Tach hours from now
          </label>
          <input
            id="recheck_hours"
            name="recheck_hours"
            type="number"
            inputMode="decimal"
            step="0.1"
            min="0.1"
            defaultValue={tachHours ?? ""}
            placeholder="10"
            className={`${FIELD} numeric`}
          />
          <p className="mt-1.5 text-[13px] text-muted">
            Hours of flying, not days. Counted from the tach as it stands when you
            save.
          </p>
        </div>
      )}

      {choice === "date" && (
        <div className="mt-2.5">
          <label htmlFor="recheck_on" className="field-label mb-1.5 block">
            Re-check on
          </label>
          <input
            id="recheck_on"
            name="recheck_on"
            type="date"
            defaultValue={on ?? ""}
            className={`${FIELD} numeric`}
          />
        </div>
      )}
    </div>
  );
}
