/**
 * The look of a form control, from the wireframes' input styling.
 *
 * A constant rather than a `@utility` in globals.css because some controls need
 * to override part of it -- a textarea is not 48px tall -- and a Tailwind
 * utility cannot be reliably overridden by another utility in the same layer.
 */
export const FIELD =
  "h-12 w-full rounded-[10px] border border-field bg-surface px-3 text-base font-medium text-ink";
