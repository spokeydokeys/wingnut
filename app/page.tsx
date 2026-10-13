import Link from "next/link";

import { Chip } from "@/components/chip";
import { TabBar } from "@/components/tab-bar";
import { TimerButton } from "@/components/timer-button";
import { requireMember } from "@/lib/dal";
import { getAircraft, getBalance, getRunningFlight } from "@/lib/flights";
import { formatMoney } from "@/lib/format";
import { logPastFlight } from "@/app/flight/actions";

// Nothing on this page is cacheable: it shows a balance and whether the timer
// is running right now.
export const dynamic = "force-dynamic";

/**
 * Home. SPEC.md 3 names the one thing this screen exists for -- start the
 * timer -- so that button is 128px tall and everything else is smaller than it.
 *
 * The snags and next-booking cards from the wireframe are missing because the
 * tables behind them do not exist yet. An empty card that always says the same
 * thing would be worse than no card.
 */
export default async function Home() {
  const member = await requireMember();
  const [aircraft, running] = await Promise.all([getAircraft(), getRunningFlight()]);
  const balance = await getBalance(member.id);

  const initials = member.full_name
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? "")
    .join("");

  return (
    <>
      <header className="flex flex-none items-center justify-between px-4 pt-4 pb-1">
        <div>
          <div className="numeric text-[22px] tracking-[1px]">
            {aircraft?.registration ?? "No aircraft"}
          </div>
          <div className="text-[13px] text-muted">
            {aircraft?.nickname ?? "Shared aircraft"}
          </div>
        </div>
        <div
          title={member.full_name}
          className="flex size-10 items-center justify-center rounded-full border-[1.5px] border-ink text-sm font-semibold"
        >
          {initials}
        </div>
      </header>

      <main className="flex min-h-0 flex-1 flex-col gap-3 px-4 pt-3 pb-4">
        {running ? (
          <Link
            href="/flight"
            className="flex flex-none flex-col justify-center gap-1 rounded-2xl bg-accent px-5 py-6 text-white"
          >
            <div className="flex items-center justify-between">
              <span className="text-[28px] font-semibold">Flight running</span>
              <Chip tone="running">Running</Chip>
            </div>
            <span className="text-[15px] opacity-90">
              {running.pilot_member_id === member.id
                ? "Tap to see the timer and stop the flight"
                : "Another owner has the clock running"}
            </span>
          </Link>
        ) : (
          <TimerButton action="start" />
        )}

        <form action={logPastFlight} className="flex flex-none justify-center">
          <button
            type="submit"
            className="flex min-h-11 items-center justify-center text-[15px] text-muted"
          >
            Already flown?
            <span className="ml-1.5 font-semibold text-ink underline">
              Log a past flight
            </span>
          </button>
        </form>

        <div className="flex flex-none items-center gap-3 rounded-[14px] border border-line bg-surface p-3.5">
          <div className="flex-1">
            <div className="field-label">
              {balance > 0 ? "You owe" : "Your balance"}
            </div>
            <div className="numeric text-[32px] leading-tight">
              {formatMoney(Math.abs(balance))}
            </div>
            <div className="text-[13px] text-muted">
              {balance > 0
                ? "Across all unpaid bills"
                : balance < 0
                  ? "In credit"
                  : "Nothing outstanding"}
            </div>
          </div>
          <Link
            href="/bills"
            className="flex h-13 w-28 items-center justify-center rounded-xl bg-ink text-base font-semibold text-white"
          >
            {balance > 0 ? "Pay bill" : "Bills"}
          </Link>
        </div>
      </main>

      <TabBar />
    </>
  );
}
