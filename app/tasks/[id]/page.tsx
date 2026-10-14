import { notFound } from "next/navigation";

import {
  cancelTask,
  completeTask,
  reassignTask,
  reopenTask,
} from "@/app/tasks/actions";
import { BackHeader } from "@/components/back-header";
import { FIELD } from "@/components/field";
import { requireMember } from "@/lib/dal";
import { getPilotChoices } from "@/lib/flights";
import { describeDue, getTask } from "@/lib/tasks";
import { formatDayShort } from "@/lib/time";

export const dynamic = "force-dynamic";

/**
 * One task: hand it over, tick it off, or drop it.
 *
 * Done is the primary button and reassign is the form, because ticking is what
 * happens to most tasks and handing one over is the exception. Neither is
 * limited to the assignee: between two owners, "I'll take that one" is the
 * normal way a rotation stays fair, and the record of who actually did it is
 * stamped by the database from whoever tapped Done.
 */
export default async function TaskDetail({ params }: PageProps<"/tasks/[id]">) {
  const { id } = await params;
  const member = await requireMember();

  const task = await getTask(id);
  if (!task) notFound();

  const people = await getPilotChoices();
  const due = describeDue(task.due_date);

  const subtitle =
    task.status === "open"
      ? due.text
      : task.status === "cancelled"
        ? "Dropped"
        : `Done ${task.completed_at ? formatDayShort(task.completed_at) : ""} by ${
            task.completed_by_name ?? "a former owner"
          }`;

  return (
    <>
      <BackHeader href="/tasks" label="Tasks" title={task.title} subtitle={subtitle} />

      <main className="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto px-4 pt-3.5 pb-4">
        {task.detail && (
          <p className="flex-none rounded-[14px] border border-line bg-surface px-3.5 py-3 text-[15px]">
            {task.detail}
          </p>
        )}

        {task.status === "open" ? (
          <>
            <form action={completeTask.bind(null, task.id)} className="flex-none">
              <button
                type="submit"
                className="flex h-14 w-full items-center justify-center rounded-[14px] bg-accent text-lg font-semibold text-white"
              >
                {task.assignee_member_id === member.id
                  ? "Done"
                  : "Done — I did this one"}
              </button>
            </form>

            {/*
              Not an ActionForm: that one owns a screen and pins its button to
              the bottom, which here would put a second full-width primary
              button opposite Done.
            */}
            <form action={reassignTask.bind(null, task.id)} className="flex-none">
              <label htmlFor="assignee_member_id" className="field-label mb-1.5 block">
                Whose it is
              </label>
              <select
                id="assignee_member_id"
                name="assignee_member_id"
                defaultValue={task.assignee_member_id ?? ""}
                className={FIELD}
              >
                <option value="">Nobody yet</option>
                {people.map((person) => (
                  <option key={person.id} value={person.id}>
                    {person.full_name}
                  </option>
                ))}
              </select>
              <button
                type="submit"
                className="mt-2.5 flex h-12 w-full items-center justify-center rounded-xl border-[1.5px] border-ink bg-surface text-base font-semibold"
              >
                Hand it over
              </button>
            </form>

            <form action={cancelTask.bind(null, task.id)} className="mt-1 flex-none">
              <button
                type="submit"
                className="flex min-h-11 w-full items-center justify-center text-[15px] font-medium text-muted underline"
              >
                Drop it — this no longer needs doing
              </button>
            </form>
          </>
        ) : (
          <>
            {/*
              Re-opening leaves any successor the tick spawned alone: it is
              already somebody else's open task, and `task_spawn_successor`
              will not make a second when this is ticked again.
            */}
            <form action={reopenTask.bind(null, task.id)} className="flex-none">
              <button
                type="submit"
                className="flex h-12 w-full items-center justify-center rounded-xl border-[1.5px] border-ink bg-surface text-base font-semibold"
              >
                Re-open it
              </button>
            </form>
            <p className="flex-none text-center text-[13px] text-muted">
              If a recurring chore already came back round, re-opening this does
              not take it away from whoever has it now.
            </p>
          </>
        )}
      </main>
    </>
  );
}
