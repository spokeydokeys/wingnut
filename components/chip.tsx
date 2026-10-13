import type { ReactNode } from "react";

// The small uppercase status pill. Four tones, matching the wireframes:
// `snag` for something wrong now, `caution` for something coming due,
// `neutral` for a state with no urgency, `running` for the live timer.
const TONES = {
  snag: "bg-snag text-snag-text border-snag-line",
  caution: "bg-caution text-caution-text border-caution-line",
  neutral: "bg-neutral-chip text-neutral-chip-text border-line",
  running: "bg-snag text-snag-text border-snag-line",
} as const;

export function Chip({
  tone,
  children,
}: {
  tone: keyof typeof TONES;
  children: ReactNode;
}) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[11px] font-semibold tracking-wider uppercase ${TONES[tone]}`}
    >
      {tone === "running" && (
        <span aria-hidden="true" className="size-2 rounded-full bg-accent" />
      )}
      {children}
    </span>
  );
}
