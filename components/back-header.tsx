import Link from "next/link";
import type { ReactNode } from "react";

/**
 * The back-arrow header on a screen that is not a tab.
 *
 * Deliberately a Link to a known parent rather than `router.back()`: these
 * screens are reached from the Aircraft tab but also by a redirect after
 * saving, and browser history would then point at a form that has already been
 * submitted.
 */
export function BackHeader({
  href,
  label,
  title,
  subtitle,
  action,
}: {
  href: string;
  label: string;
  title: string;
  subtitle?: string;
  /**
   * The one thing this screen is for, if it is a list you add to. Sits beside
   * the back arrow rather than beside the title, so a long title can wrap
   * without pushing it off the edge.
   */
  action?: ReactNode;
}) {
  return (
    <>
      <header className="flex min-h-14 flex-none items-center justify-between py-3 pr-4 pl-2">
        <Link
          href={href}
          className="flex min-h-11 items-center gap-0.5 px-2 text-base font-medium"
        >
          <svg
            aria-hidden="true"
            width="24"
            height="24"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path d="M15 5l-7 7 7 7" />
          </svg>
          {label}
        </Link>
        {action}
      </header>

      <div className="flex-none px-4">
        <h1 className="text-[26px] font-semibold">{title}</h1>
        {subtitle && <p className="mt-0.5 text-sm text-muted">{subtitle}</p>}
      </div>
    </>
  );
}
