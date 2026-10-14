import Link from "next/link";

import { Chip } from "@/components/chip";
import { TabBar } from "@/components/tab-bar";
import { TaskRow } from "@/components/task-row";
import { TimerButton } from "@/components/timer-button";
import { getLiveSnags } from "@/lib/aircraft";
import { requireMember } from "@/lib/dal";
import { getAircraft, getBalance, getRunningFlight } from "@/lib/flights";
import { formatMoney } from "@/lib/format";
import { getMyOpenTasks } from "@/lib/tasks";
import { logPastFlight } from "@/app/flight/actions";

// Nothing on this page is cacheable: it shows a balance and whether the timer
// is running right now.
export const dynamic = "force-dynamic";

/**
 * Home. SPEC.md 3 names the one thing this screen exists for -- start the
 * timer -- so that button is 128px tall and everything else is smaller than it.
 *
 * The snag and task cards appear only when there is something to say, so
 * nothing on this screen is a card that always reads the same.
 *
 * There is no next-booking card. The wireframes had one, from when the
 * calendar was a door behind More and this was the only place it showed. Now
 * that Bookings is a tab, the card was a second-hand copy of the first line of
 * a screen one tap away -- and the tap is the thing you want anyway, because
 * the card could not be booked from.
 */
export default async function Home() {
  const member = await requireMember();
  const [aircraft, running] = await Promise.all([getAircraft(), getRunningFlight()]);
  const [balance, snags, tasks] = await Promise.all([
    getBalance(member.id),
    aircraft ? getLiveSnags(aircraft.id) : Promise.resolve([]),
    getMyOpenTasks(member.id),
  ]);

  const openSnags = snags.filter((snag) => snag.status === "open").length;
  const grounded = snags.some((snag) => snag.grounding);

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

      <main className="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto px-4 pt-3 pb-4">
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

        {/*
          Second, by the owner's own ordering: timer, receipt, snags, tasks,
          balance. It is here rather than behind More because a receipt is
          photographed at the dock with the engine still ticking, and the one
          thing that loses a $250 reimbursement is having to go looking for
          this screen.
        */}
        <Link
          href="/receipts/new"
          className="flex flex-none items-center justify-between gap-3 rounded-[14px] border border-line bg-surface p-3.5"
        >
          <span>
            <span className="field-label block">Receipts</span>
            <span className="block text-base font-semibold">Add a receipt</span>
            <span className="block text-[13px] text-muted">
              Fuel you buy comes back in full on your next bill
            </span>
          </span>
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
            className="flex-none text-muted"
          >
            <path d="M9 5l7 7-7 7" />
          </svg>
        </Link>

        {/*
          Snags and tasks, in that order, and only when there are any. A snag
          is about the aeroplane and so is everybody's; the tasks below are
          only the reader's own, because the whole list lives on its own screen.
        */}
        {snags.length > 0 && (
          <Link
            href="/aircraft"
            className={`flex flex-none items-center justify-between gap-3 rounded-[14px] border bg-surface p-3.5 ${
              grounded ? "border-snag-line" : "border-line"
            }`}
          >
            <span>
              <span className="field-label block">Snags</span>
              <span className="block text-base font-semibold">
                {openSnags > 0
                  ? `${openSnags} open`
                  : `${snags.length} to watch`}
                {openSnags > 0 && snags.length > openSnags
                  ? `, ${snags.length - openSnags} to watch`
                  : ""}
              </span>
              <span className="block text-[13px] text-muted">
                {snags[0].title}
                {snags.length > 1 && ` · and ${snags.length - 1} more`}
              </span>
            </span>
            {grounded && (
              <span className="flex-none">
                <Chip tone="snag">Grounded</Chip>
              </span>
            )}
          </Link>
        )}

        {tasks.length > 0 && (
          <div className="flex-none rounded-[14px] border border-line bg-surface px-3.5 pb-1">
            <div className="flex items-center justify-between pt-3">
              <h2 className="field-label">Your tasks</h2>
              <Link href="/tasks" className="text-sm font-semibold text-accent">
                {tasks.length > 3 ? `All ${tasks.length}` : "All tasks"}
              </Link>
            </div>
            <div className="divide-y divide-hairline">
              {tasks.slice(0, 3).map((task) => (
                <TaskRow key={task.id} task={task} memberId={member.id} />
              ))}
            </div>
          </div>
        )}

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
