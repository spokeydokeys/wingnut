import Link from "next/link";

import { BackHeader } from "@/components/back-header";
import { TaskRow } from "@/components/task-row";
import { requireMember } from "@/lib/dal";
import {
  describeRecurrence,
  getOpenTasks,
  getSettledTasks,
  getTaskSeries,
} from "@/lib/tasks";
import { formatDayMonth } from "@/lib/time";

// Overdue is arithmetic on today's date, which moves on its own.
export const dynamic = "force-dynamic";

/**
 * The admin chores: what is on each person's list, and what comes back.
 *
 * Split into yours and everyone else's rather than one list sorted by date,
 * because the question an owner opens this screen with is "what do I owe", and
 * the second list is there so that the answer is checkable -- a rotation only
 * works if you can see whose turn it was.
 *
 * The recurring panel shows the whole rotation, not just the next name. Being
 * told it is your turn is easier to accept when the order is visible.
 */
export default async function Tasks() {
  const member = await requireMember();

  const [open, series, settled] = await Promise.all([
    getOpenTasks(),
    getTaskSeries(),
    getSettledTasks(),
  ]);

  const mine = open.filter((task) => task.assignee_member_id === member.id);
  const theirs = open.filter((task) => task.assignee_member_id !== member.id);

  return (
    <>
      <BackHeader
        href="/more"
        label="More"
        title="Tasks"
        action={
          <Link
            href="/tasks/new"
            className="flex h-11 items-center rounded-[10px] border-[1.5px] border-ink bg-surface px-4 text-[15px] font-semibold"
          >
            + Task
          </Link>
        }
      />

      <main className="flex min-h-0 flex-1 flex-col gap-2.5 overflow-y-auto px-4 pt-3.5 pb-4">
        <h2 className="field-label px-0.5">Yours</h2>
        {mine.length === 0 ? (
          <p className="flex-none rounded-[14px] border border-line bg-surface px-3.5 py-3 text-[15px] text-muted">
            Nothing on your list.
          </p>
        ) : (
          <div className="flex-none divide-y divide-hairline rounded-[14px] border border-line bg-surface px-3.5">
            {mine.map((task) => (
              <TaskRow key={task.id} task={task} memberId={member.id} />
            ))}
          </div>
        )}

        {theirs.length > 0 && (
          <>
            <h2 className="field-label mt-1.5 px-0.5">Everyone else</h2>
            <div className="flex-none divide-y divide-hairline rounded-[14px] border border-line bg-surface px-3.5">
              {theirs.map((task) => (
                <TaskRow key={task.id} task={task} memberId={member.id} />
              ))}
            </div>
          </>
        )}

        <div className="mt-1.5 flex items-center justify-between px-0.5">
          <h2 className="field-label">Recurring</h2>
          {member.role === "admin" && (
            <Link
              href="/tasks/series/new"
              className="flex min-h-11 items-center text-sm font-semibold text-accent"
            >
              Add a chore
            </Link>
          )}
        </div>

        {series.length === 0 ? (
          <p className="flex-none rounded-[14px] border border-line bg-surface px-3.5 py-3 text-[15px] text-muted">
            No recurring chores. Closing a month spawns one for each chore set up
            here, so the month-end reconcile belongs in this list.
          </p>
        ) : (
          series.map((chore) => {
            const body = (
              <>
                <div className="text-base font-semibold">{chore.title}</div>
                <div className="mt-1 text-[13px] text-muted">
                  {describeRecurrence(chore)}
                </div>
                <div className="mt-1 text-[13px]">
                  {chore.next_name === null ? (
                    <span className="text-muted">
                      Nobody is in the rotation
                      {chore.admins_only && " — it is limited to admins"}
                    </span>
                  ) : (
                    <>
                      Next turn:{" "}
                      <span className="font-semibold">{chore.next_name}</span>
                      {chore.rotation_names.length > 1 && (
                        <span className="text-muted">
                          {" "}
                          · rotation {chore.rotation_names.join(" → ")}
                        </span>
                      )}
                    </>
                  )}
                </div>
              </>
            );

            const card =
              "flex-none rounded-[14px] border border-line bg-surface px-3.5 py-3";

            // Stopping a chore used to be a button in this card, and it is now
            // on the chore's own screen instead -- so the whole card is one tap
            // target, the way a task row is, and nothing destructive sits under
            // a thumb scrolling the list. Only an admin gets the link, because
            // only an admin can change a chore.
            return member.role === "admin" ? (
              <Link key={chore.id} href={`/tasks/series/${chore.id}`} className={card}>
                {body}
              </Link>
            ) : (
              <div key={chore.id} className={card}>
                {body}
              </div>
            );
          })
        )}

        {settled.length > 0 && (
          <>
            <h2 className="field-label mt-1.5 px-0.5">Lately</h2>
            <div className="flex-none divide-y divide-hairline rounded-[14px] border border-line bg-surface px-3.5">
              {settled.map((task) => (
                <Link
                  key={task.id}
                  href={`/tasks/${task.id}`}
                  className="flex items-center justify-between gap-2.5 py-3"
                >
                  <span className="min-w-0">
                    <span className="block truncate text-[15px] font-medium">
                      {task.title}
                    </span>
                    <span className="block text-[13px] text-muted">
                      {task.status === "cancelled"
                        ? "Dropped"
                        : `Done${
                            task.completed_at
                              ? ` ${formatDayMonth(task.completed_at)}`
                              : ""
                          } by ${task.completed_by_name ?? "a former owner"}`}
                    </span>
                  </span>
                </Link>
              ))}
            </div>
          </>
        )}
      </main>
    </>
  );
}
