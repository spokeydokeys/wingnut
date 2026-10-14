"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireAdmin, requireMember } from "@/lib/dal";
import { getAircraft } from "@/lib/flights";
import { createClient } from "@/lib/supabase/server";

/**
 * Server Actions for the tasks tab.
 *
 * Who completed a chore is never passed in: `task_stamp_completed` reads it
 * from `current_member_id()`, and `task_spawn_successor` then decides whose
 * turn is next from that. So "tick it" here is one status update, and the
 * rotation follows from the database rather than from anything a client sends.
 *
 * Reassignment is open to any member, which is what `task_update_members`
 * says. Two owners swapping a chore between them does not need an approval
 * step, and the record of who actually did it is the completion stamp.
 */

type Failed = { error: string };

const UUID = /^[0-9a-f-]{36}$/i;
const DATE = /^\d{4}-\d{2}-\d{2}$/;

/** One place, so a new screen cannot forget one of the lists. */
function revalidateTasks() {
  revalidatePath("/", "layout");
}

/**
 * Ticks a chore off.
 *
 * The successor is spawned by `task_spawn_successor`, not here, because the
 * month-close path writes tasks too and a rule living in the action would only
 * apply to the ones ticked on this screen.
 */
export async function completeTask(taskId: string) {
  await requireMember();

  const supabase = await createClient();
  const { error } = await supabase
    .from("task")
    .update({ status: "done" })
    .eq("id", taskId);
  if (error) throw error;

  revalidateTasks();
}

/**
 * Un-ticks one, for the chore marked done by mistake.
 *
 * The successor the tick spawned is left alone: it is already somebody else's
 * open task, and deleting it from under them would be worse than the duplicate.
 * `task_spawn_successor`'s "no open one exists" guard means re-ticking this
 * will not spawn a second.
 */
export async function reopenTask(taskId: string) {
  await requireMember();

  const supabase = await createClient();
  const { error } = await supabase
    .from("task")
    .update({ status: "open" })
    .eq("id", taskId);
  if (error) throw error;

  revalidateTasks();
}

/** For the chore that stopped mattering. Cancelled, not deleted: it is a record. */
export async function cancelTask(taskId: string) {
  await requireMember();

  const supabase = await createClient();
  const { error } = await supabase
    .from("task")
    .update({ status: "cancelled" })
    .eq("id", taskId);
  if (error) throw error;

  revalidateTasks();
}

/**
 * Hands a chore to somebody else, or to nobody.
 *
 * Throws rather than returning a complaint, because the only thing it can
 * object to is an id that is not a uuid, and the only control that calls it is
 * a `<select>` the server rendered from the roster.
 */
export async function reassignTask(taskId: string, form: FormData) {
  await requireMember();

  const assignee = String(form.get("assignee_member_id") ?? "");
  if (assignee !== "" && !UUID.test(assignee)) {
    throw new Error("That person could not be read.");
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("task")
    .update({ assignee_member_id: assignee === "" ? null : assignee })
    .eq("id", taskId);
  if (error) throw error;

  revalidateTasks();
  redirect("/tasks");
}

/**
 * A one-off: ring the hangar owner about the leak.
 *
 * No series, so nothing spawns a successor when it is done. A due date is
 * optional -- `getOpenTasks` sorts a dateless one last rather than first,
 * because "sometime" is not more urgent than a dated chore.
 */
export async function createTask(
  _prev: Failed | null,
  form: FormData,
): Promise<Failed | never> {
  const member = await requireMember();
  const aircraft = await getAircraft();
  if (!aircraft) return { error: "No aircraft has been set up yet." };

  const title = String(form.get("title") ?? "").trim();
  if (title === "") return { error: "Give the task a title." };

  const dueDate = String(form.get("due_date") ?? "").trim();
  if (dueDate !== "" && !DATE.test(dueDate)) {
    return { error: "That date could not be read." };
  }

  const assignee = String(form.get("assignee_member_id") ?? "");
  if (assignee !== "" && !UUID.test(assignee)) {
    return { error: "That person could not be read." };
  }

  const supabase = await createClient();
  const { error } = await supabase.from("task").insert({
    company_id: aircraft.company_id,
    title,
    detail: String(form.get("detail") ?? "").trim() || null,
    assignee_member_id: assignee === "" ? null : assignee,
    due_date: dueDate === "" ? null : dueDate,
    created_by: member.id,
  });

  if (error) return { error: error.message };

  revalidateTasks();
  redirect("/tasks");
}

/** What a chore is, less which company it belongs to. */
type SeriesFields = {
  title: string;
  detail: string | null;
  recurrence: "month_close" | "interval_days";
  interval_days: number | null;
  due_offset_days: number;
  admins_only: boolean;
};

/**
 * Reads a chore off either of its two forms.
 *
 * Shared so that adding one and editing one cannot come to disagree about what
 * a valid chore is -- the failure that mattered would be the quiet direction,
 * where the editor accepts something the creator would have refused and the
 * check constraint is the only thing left objecting.
 */
function readSeriesFields(form: FormData): Failed | SeriesFields {
  const title = String(form.get("title") ?? "").trim();
  if (title === "") return { error: "Give the chore a title." };

  const recurrence = String(form.get("recurrence") ?? "");
  if (recurrence !== "month_close" && recurrence !== "interval_days") {
    return { error: "A chore either follows a month close or repeats on a count of days." };
  }

  // Which of the two numbers is read depends on the recurrence, matching
  // `task_series_interval_matches_recurrence`: an interval on a month-close
  // chore would be a number nothing ever looks at.
  let intervalDays: number | null = null;
  let dueOffsetDays = 0;

  if (recurrence === "interval_days") {
    intervalDays = Number(String(form.get("interval_days") ?? "").trim());
    if (!Number.isInteger(intervalDays) || intervalDays < 1) {
      return { error: "Say how many days between turns." };
    }
  } else {
    const raw = String(form.get("due_offset_days") ?? "0").trim();
    dueOffsetDays = raw === "" ? 0 : Number(raw);
    if (!Number.isInteger(dueOffsetDays) || dueOffsetDays < 0) {
      return { error: "The days after month end has to be a whole number." };
    }
  }

  return {
    title,
    detail: String(form.get("detail") ?? "").trim() || null,
    recurrence,
    interval_days: intervalDays,
    due_offset_days: dueOffsetDays,
    admins_only: form.get("admins_only") === "on",
  };
}

/**
 * A recurring chore.
 *
 * Admin-only, and this exists rather than being seed-only because the seed
 * never runs against a hosted database: without this form a production company
 * would have no reconcile series, and closing a month would spawn nothing --
 * which is the whole reason the feature was asked for.
 *
 * requireAdmin() rather than leaning on `task_series_admin_write` alone: the
 * policy refuses either way, but it would refuse an UPDATE by silently
 * matching no rows, which reads on screen as "saved" and nothing changing.
 */
export async function createTaskSeries(
  _prev: Failed | null,
  form: FormData,
): Promise<Failed | never> {
  await requireAdmin();
  const aircraft = await getAircraft();
  if (!aircraft) return { error: "No aircraft has been set up yet." };

  const fields = readSeriesFields(form);
  if ("error" in fields) return fields;

  const supabase = await createClient();
  const { error } = await supabase
    .from("task_series")
    .insert({ company_id: aircraft.company_id, ...fields });

  if (error) return { error: error.message };

  revalidateTasks();
  redirect("/tasks");
}

/**
 * Corrects a chore: its wording, how often it comes round, who is in for it.
 *
 * The tasks already spawned from it are left exactly as they are. A task's
 * title is a copy taken when it spawned, and that is deliberate -- the chore
 * somebody already ticked off should keep the words it had when they did it,
 * because the "Lately" list is the evidence the rotation is judged by. So a
 * rename reaches the next turn, not the last one.
 *
 * Whose turn is next is not editable here because it is not stored: it is
 * derived from the roster and from who completed the previous turn. Narrowing
 * a chore to admins changes the rotation; nothing else on this screen does.
 */
export async function updateTaskSeries(
  seriesId: string,
  _prev: Failed | null,
  form: FormData,
): Promise<Failed | never> {
  await requireAdmin();

  const fields = readSeriesFields(form);
  if ("error" in fields) return fields;

  const supabase = await createClient();
  // Selecting the id back is the only way to tell a refused UPDATE from an
  // applied one: RLS declines by matching no rows, not by raising, and a
  // no-op that redirected would read on screen as a save.
  const { data, error } = await supabase
    .from("task_series")
    .update(fields)
    .eq("id", seriesId)
    .select("id");

  if (error) return { error: error.message };
  if (!data || data.length === 0) return { error: "That chore could not be saved." };

  revalidateTasks();
  redirect("/tasks");
}

/**
 * Stops a chore coming back.
 *
 * Deactivated rather than deleted: the series is what the finished tasks point
 * at, and the history of who took which turn is the reason the rotation is
 * believable to whoever is next.
 */
export async function retireTaskSeries(seriesId: string) {
  await requireAdmin();

  const supabase = await createClient();
  const { error } = await supabase
    .from("task_series")
    .update({ is_active: false })
    .eq("id", seriesId);
  if (error) throw error;

  revalidateTasks();
}
