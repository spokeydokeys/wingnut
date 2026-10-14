import Link from "next/link";

export type BookingView = "agenda" | "month";

/**
 * Agenda or month.
 *
 * Links rather than tabs holding client state, so the view is in the URL: the
 * calendar is the screen an owner sends to the other one ("look at the 19th"),
 * and a view that lived in a component would not survive being sent, reloaded
 * or come back to from a booking.
 *
 * The agenda is the bare /bookings path rather than ?view=agenda, so the one
 * link on the More tab lands somewhere canonical.
 */
const VIEWS: { key: BookingView; label: string; href: string }[] = [
  { key: "agenda", label: "Agenda", href: "/bookings" },
  { key: "month", label: "Month", href: "/bookings?view=month" },
];

export function BookingViewSwitcher({ current }: { current: BookingView }) {
  return (
    <nav className="flex flex-none gap-1 rounded-[12px] border border-line bg-surface p-1">
      {VIEWS.map((view) => (
        <Link
          key={view.key}
          href={view.href}
          aria-current={view.key === current ? "page" : undefined}
          className={`flex h-9 flex-1 items-center justify-center rounded-[9px] text-[14px] font-semibold ${
            view.key === current ? "bg-ink text-white" : "text-muted"
          }`}
        >
          {view.label}
        </Link>
      ))}
    </nav>
  );
}
