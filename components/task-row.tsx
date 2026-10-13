import Link from "next/link";

import { Chip } from "@/components/chip";
import { describeDue, type TaskWithNames } from "@/lib/tasks";

/**
 * One open task, in the list on the tasks screen and on the Home card.
 *
 * The due date is a chip rather than a line of text because overdue is the one
 * thing that has to survive being skimmed; `describeDue` works it out against
 * today, which moves, so nothing is stored.
 *
 * Whose it is sits under the title, and reads "Yours" rather than the owner's
 * own name -- on Home the list is already only theirs, and on the tasks screen
 * it is the difference that matters.
 */
export function TaskRow({
  task,
  memberId,
}: {
  task: TaskWithNames;
  memberId: string;
}) {
  const due = describeDue(task.due_date);
  const who =
    task.assignee_member_id === null
      ? "Nobody yet"
      : task.assignee_member_id === memberId
        ? "Yours"
        : task.assignee_name ?? "A former owner";

  return (
    <Link
      href={`/tasks/${task.id}`}
      className="flex items-start justify-between gap-2.5 py-3"
    >
      <span className="min-w-0">
        <span className="block text-base font-semibold">{task.title}</span>
        {/*
          The detail is clamped and the title is not: a title is the whole of
          what the task is, while the detail is a reminder that can be read on
          the task's own screen.
        */}
        <span className="mt-0.5 line-clamp-2 text-[13px] text-muted">
          {who}
          {task.detail && ` · ${task.detail}`}
        </span>
      </span>
      <span className="mt-0.5 flex-none">
        <Chip tone={due.overdue ? "caution" : "neutral"}>{due.text}</Chip>
      </span>
    </Link>
  );
}
