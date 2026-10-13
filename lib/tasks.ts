import "server-only";

import { createClient } from "./supabase/server";
import { toDateInputValue } from "./time";
import type { Database } from "./database.types";

export type Task = Database["public"]["Tables"]["task"]["Row"];
export type TaskSeries = Database["public"]["Tables"]["task_series"]["Row"];

/** A task with the names filled in, which is all any screen wants. */
export type TaskWithNames = Task & {
  assignee_name: string | null;
  completed_by_name: string | null;
};

/**
 * Reads for the Home card, the task list and the recurring-chore panel.
 *
 * Nothing here stores or caches whether a task is overdue: that is arithmetic
 * on today's date, which moves on its own, so it is computed where it is read.
 * Same reason `maintenance_status` is a view rather than a column.
 */

/** id -> full name, for the two or three people on the roster. */
async function nameMap(): Promise<Map<string, string>> {
  const supabase = await createClient();
  const { data } = await supabase.from("member").select("id, full_name");
  return new Map((data ?? []).map((m) => [m.id, m.full_name]));
}

function withNames(tasks: Task[], names: Map<string, string>): TaskWithNames[] {
  return tasks.map((task) => ({
    ...task,
    assignee_name: task.assignee_member_id
      ? (names.get(task.assignee_member_id) ?? null)
      : null,
    completed_by_name: task.completed_by
      ? (names.get(task.completed_by) ?? null)
      : null,
  }));
}

/**
 * Everything still open, soonest first.
 *
 * A task with no date sorts last rather than first: "ring the hangar owner
 * sometime" is a real task, but it is not more urgent than one with a date on
 * it, which is what ascending nulls would make it look like.
 */
export async function getOpenTasks(): Promise<TaskWithNames[]> {
  const supabase = await createClient();
  const [{ data }, names] = await Promise.all([
    supabase
      .from("task")
      .select("*")
      .eq("status", "open")
      .order("due_date", { ascending: true, nullsFirst: false })
      .order("created_at", { ascending: true }),
    nameMap(),
  ]);
  return withNames(data ?? [], names);
}

/** The open tasks belonging to one person. The Home card. */
export async function getMyOpenTasks(memberId: string): Promise<TaskWithNames[]> {
  const tasks = await getOpenTasks();
  return tasks.filter((task) => task.assignee_member_id === memberId);
}

/**
 * The last few finished or dropped ones.
 *
 * Worth a screen because it is the record of who took which turn -- the reason
 * the rotation is believable to the person whose turn it is next.
 */
export async function getSettledTasks(limit = 12): Promise<TaskWithNames[]> {
  const supabase = await createClient();
  const [{ data }, names] = await Promise.all([
    supabase
      .from("task")
      .select("*")
      .neq("status", "open")
      .order("completed_at", { ascending: false, nullsFirst: false })
      .order("updated_at", { ascending: false })
      .limit(limit),
    nameMap(),
  ]);
  return withNames(data ?? [], names);
}

/** A recurring chore, with whose turn is next and who is in the rotation. */
export type SeriesWithRotation = TaskSeries & {
  next_name: string | null;
  rotation_names: string[];
};

/**
 * The live recurring chores.
 *
 * Whose turn is next comes from `task_next_assignee` rather than being worked
 * out here. It is the same question the triggers answer when they spawn the
 * next one, and a second implementation in TypeScript would eventually tell
 * somebody their turn had come round when it had not.
 */
export async function getTaskSeries(): Promise<SeriesWithRotation[]> {
  const supabase = await createClient();
  const [{ data }, names] = await Promise.all([
    supabase
      .from("task_series")
      .select("*")
      .eq("is_active", true)
      .order("title"),
    nameMap(),
  ]);

  return Promise.all(
    (data ?? []).map(async (series) => {
      const [{ data: next }, { data: rotation }] = await Promise.all([
        supabase.rpc("task_next_assignee", { p_series_id: series.id }),
        supabase.rpc("task_rotation", { p_series_id: series.id }),
      ]);

      return {
        ...series,
        next_name: next ? (names.get(next) ?? null) : null,
        rotation_names: [...(rotation ?? [])]
          .sort((a, b) => (a.turn ?? 0) - (b.turn ?? 0))
          .map((row) => (row.member_id ? (names.get(row.member_id) ?? "?") : "?")),
      };
    }),
  );
}

/**
 * How a due date reads, and whether it should look like a warning.
 *
 * Today counts as due, not overdue -- a chore due today is a chore for today.
 * The comparison is against the date where the aeroplane is, matching
 * `aircraft_today()`, so an owner opening the app from a hotel in Toronto does
 * not see tomorrow's chores as today's.
 */
export function describeDue(dueDate: string | null): {
  text: string;
  overdue: boolean;
} {
  if (!dueDate) return { text: "No date", overdue: false };

  const today = toDateInputValue();
  if (dueDate > today) return { text: `Due ${formatShortDate(dueDate)}`, overdue: false };
  if (dueDate === today) return { text: "Due today", overdue: false };

  const days = daysBetween(dueDate, today);
  return {
    text: days === 1 ? "1 day overdue" : `${days} days overdue`,
    overdue: true,
  };
}

/** `10 Nov`, from a plain date and without going near a time zone. */
function formatShortDate(isoDate: string): string {
  const [y, m, d] = isoDate.split("-").map(Number);
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: "UTC",
    day: "numeric",
    month: "short",
  }).format(new Date(Date.UTC(y, m - 1, d)));
}

/** Whole days between two `YYYY-MM-DD`s, read as UTC so neither has a zone. */
function daysBetween(from: string, to: string): number {
  const asUtc = (value: string) => {
    const [y, m, d] = value.split("-").map(Number);
    return Date.UTC(y, m - 1, d);
  };
  return Math.round((asUtc(to) - asUtc(from)) / 86_400_000);
}

/** "Every 90 days" or "When the month is closed", for the chore panel. */
export function describeRecurrence(series: TaskSeries): string {
  if (series.recurrence === "month_close") {
    return series.due_offset_days === 0
      ? "When a month is closed"
      : `When a month is closed, due ${series.due_offset_days} days after it ends`;
  }
  return series.interval_days === 1
    ? "Every day after it is done"
    : `Every ${series.interval_days} days after it is done`;
}
