"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

// The nav from the wireframes, plus bookings. SPEC.md 3 puts the calendar
// behind More, which was wrong in practice: booking the aeroplane happens for
// basically every flight, just days before it rather than at the aeroplane. A
// thing done that often is not a thing to go looking for.
//
// Five is the ceiling. This list is the whole information architecture, and
// anything else that wants on it has to argue another one off.
const TABS = [
  {
    href: "/",
    label: "Home",
    icon: (
      <>
        <path d="M3 11l9-8 9 8" />
        <path d="M5 10v10h14V10" />
      </>
    ),
  },
  {
    href: "/aircraft",
    label: "Aircraft",
    icon: <path d="M12 2l1 2v5l9 5v2l-9-2.5V19l3 2v1l-4-1-4 1v-1l3-2v-5.5L2 16v-2l9-5V4z" />,
  },
  {
    href: "/bookings",
    label: "Bookings",
    icon: (
      <>
        <rect x="3" y="5" width="18" height="16" rx="2" />
        <path d="M3 10h18" />
        <path d="M8 3v4" />
        <path d="M16 3v4" />
      </>
    ),
  },
  {
    href: "/bills",
    label: "Bills",
    icon: (
      <>
        <rect x="2" y="5" width="20" height="14" rx="2" />
        <path d="M2 10h20" />
      </>
    ),
  },
  {
    href: "/more",
    label: "More",
    icon: (
      <>
        <circle cx="5" cy="12" r="1.5" />
        <circle cx="12" cy="12" r="1.5" />
        <circle cx="19" cy="12" r="1.5" />
      </>
    ),
  },
];

export function TabBar() {
  const pathname = usePathname();

  return (
    <nav className="flex flex-none border-t border-line bg-surface pb-[env(safe-area-inset-bottom)]">
      {TABS.map((tab) => {
        // Home matches only itself; the others match their whole subtree so a
        // flight detail page still shows Aircraft as the current tab.
        const current =
          tab.href === "/" ? pathname === "/" : pathname.startsWith(tab.href);

        return (
          <Link
            key={tab.href}
            href={tab.href}
            aria-current={current ? "page" : undefined}
            className={`flex h-[68px] flex-1 flex-col items-center justify-center gap-1 text-xs ${
              current ? "font-semibold text-accent" : "text-muted"
            }`}
          >
            <svg
              aria-hidden="true"
              width="24"
              height="24"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.75"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              {tab.icon}
            </svg>
            {tab.label}
          </Link>
        );
      })}
    </nav>
  );
}
