import "server-only";

import { createClient } from "./supabase/server";
import { receiptUrl } from "./storage";
import type { Aircraft } from "./flights";
import type { Member } from "./dal";
import type { Database } from "./database.types";

export type Expense = Database["public"]["Tables"]["expense"]["Row"];
export type ExpenseStatus = Database["public"]["Enums"]["expense_status"];
export type ExpensePayer = Database["public"]["Enums"]["expense_payer"];

/** An expense account from the company's own chart. The category list IS the chart. */
export type Category = { code: string; name: string };

/** A receipt with the names and the category filled in, which is all a screen wants. */
export type ExpenseWithNames = Expense & {
  paid_by_name: string | null;
  submitted_by_name: string | null;
  reviewed_by_name: string | null;
  category_name: string;
};

/**
 * Reads for the receipts screens.
 *
 * Nothing here adds up money. The credit a receipt turns into is
 * `month_charges`' third arm and is read through lib/bills.ts like every other
 * line of a bill; a total computed here would be a second opinion about the
 * same money, which is indistinguishable from a bug until somebody is paid
 * twice.
 *
 * Editability is also not stored. Whether a receipt can still be changed is a
 * fact about its status and about whether its month has been closed since --
 * both of which move on their own -- so it is computed where it is read, the
 * same way `describeDue` works out whether a task is overdue.
 */

/** id -> full name, for the two or three people on the roster. */
async function nameMap(): Promise<Map<string, string>> {
  const supabase = await createClient();
  const { data } = await supabase.from("member").select("id, full_name");
  return new Map((data ?? []).map((m) => [m.id, m.full_name]));
}

/**
 * The categories a receipt can be coded to: the expense half of the chart.
 *
 * Read from `gl_account` rather than from a list in this file, because
 * `expense_zz_validate` refuses anything that is not an expense account in the
 * company's chart. A hard-coded list here would eventually offer a code the
 * database rejects, and the pilot would see a save fail on a choice the app
 * had given them.
 */
export async function getCategories(): Promise<Category[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("gl_account")
    .select("code, name")
    .eq("type", "expense")
    .order("code");
  return data ?? [];
}

async function categoryMap(): Promise<Map<string, string>> {
  return new Map((await getCategories()).map((c) => [c.code, c.name]));
}

function withNames(
  rows: Expense[],
  names: Map<string, string>,
  categories: Map<string, string>,
): ExpenseWithNames[] {
  return rows.map((row) => ({
    ...row,
    paid_by_name: row.paid_by_member_id
      ? (names.get(row.paid_by_member_id) ?? null)
      : null,
    submitted_by_name: names.get(row.submitted_by) ?? null,
    reviewed_by_name: row.reviewed_by ? (names.get(row.reviewed_by) ?? null) : null,
    // Falls back to the bare code rather than to "Unknown". The code is a real
    // account in the company's chart -- the foreign key says so -- so it is
    // always something an accountant can look up, even if this map was built
    // before it was added.
    category_name: categories.get(row.gl_account_code) ?? row.gl_account_code,
  }));
}

/**
 * The receipts list: everything, newest purchase first.
 *
 * Everyone's, not just yours. The approval rule is "the other co-owner", which
 * cannot work if you cannot see what you are approving, and the owner's
 * instruction on 13 Oct 2026 was that a company-card purchase must be visible
 * to the other owner too.
 */
export async function getExpenses(limit = 40): Promise<ExpenseWithNames[]> {
  const supabase = await createClient();
  const [{ data }, names, categories] = await Promise.all([
    supabase
      .from("expense")
      .select("*")
      .order("spent_on", { ascending: false })
      .order("created_at", { ascending: false })
      .limit(limit),
    nameMap(),
    categoryMap(),
  ]);
  return withNames(data ?? [], names, categories);
}

/**
 * The approvals queue: oldest first.
 *
 * Oldest first on purpose, unlike every other list in the app. This one is a
 * queue of money somebody is out of pocket for, and the right one to deal with
 * next is the one that has been waiting longest.
 */
export async function getAwaitingApproval(): Promise<ExpenseWithNames[]> {
  const supabase = await createClient();
  const [{ data }, names, categories] = await Promise.all([
    supabase
      .from("expense")
      .select("*")
      .eq("status", "submitted")
      .order("spent_on", { ascending: true }),
    nameMap(),
    categoryMap(),
  ]);
  return withNames(data ?? [], names, categories);
}

/** One receipt, for the screen that decides it. */
export async function getExpense(id: string): Promise<ExpenseWithNames | null> {
  const supabase = await createClient();
  const [{ data }, names, categories] = await Promise.all([
    supabase.from("expense").select("*").eq("id", id).maybeSingle(),
    nameMap(),
    categoryMap(),
  ]);
  if (!data) return null;
  return withNames([data], names, categories)[0];
}

/**
 * A URL for the image that works for an hour, or null if there is none.
 *
 * Null covers two different things and the detail screen must not distinguish
 * them for the viewer: no image was ever uploaded (the dock had no signal), or
 * the key points at an object that is not there. Both read as "no photo yet".
 */
export async function getReceiptUrl(expense: Expense): Promise<string | null> {
  if (!expense.receipt_key) return null;
  const supabase = await createClient();
  return receiptUrl(supabase, expense.receipt_key);
}

/**
 * The other receipts that look like this one.
 *
 * SPEC.md 4.7 asks for a flag, not a refusal, and `expense_duplicates` is the
 * one definition of "the same receipt twice" -- same vendor, same day, same
 * amount. Two real fills on one day do happen, so this warns and the pilot
 * decides.
 */
export async function getDuplicates(id: string): Promise<ExpenseWithNames[]> {
  const supabase = await createClient();
  const { data: ids } = await supabase.rpc("expense_duplicates", {
    p_expense_id: id,
  });
  if (!ids || ids.length === 0) return [];

  const [{ data }, names, categories] = await Promise.all([
    supabase.from("expense").select("*").in("id", ids),
    nameMap(),
    categoryMap(),
  ]);
  return withNames(data ?? [], names, categories);
}

/** Has an invoice for this month left draft? Asked of the database, never guessed. */
export async function isMonthClosed(
  companyId: string,
  month: string,
): Promise<boolean> {
  const supabase = await createClient();
  const { data } = await supabase.rpc("month_is_closed", {
    p_company_id: companyId,
    p_month: month,
  });
  return data === true;
}

/**
 * Why this receipt can no longer be changed, or null if it still can.
 *
 * A string rather than a boolean because the two reasons want different words
 * on screen, and "it is locked" with no reason is the kind of thing that gets
 * a text message at nine at night.
 *
 * `monthClosed` is passed in rather than looked up: the caller already has to
 * ask the database, and a function that awaited inside itself could not be
 * used while rendering a list.
 */
export function lockReason(
  expense: Expense,
  monthClosed: boolean,
): string | null {
  if (expense.status === "approved") {
    return "Agreed receipts cannot be changed. Raise an adjustment instead.";
  }
  if (expense.status === "recorded" && monthClosed) {
    return "This month has been billed, so its coding is settled.";
  }
  return null;
}

/**
 * May this member decide this receipt?
 *
 * The real rule is in `expense_zz_validate`, which raises; this is the same
 * rule again so the button can be absent rather than present and failing.
 * Deliberately a copy and deliberately the looser of the two: if these ever
 * disagree the database wins, and the worst case is a button that explains
 * itself with an error rather than a receipt nobody can approve.
 */
export function canReview(
  expense: Expense,
  member: Member,
  aircraft: Aircraft,
): boolean {
  if (expense.status !== "submitted") return false;
  if (aircraft.expense_approval_rule === "admin_only") {
    return member.role === "admin";
  }
  return expense.paid_by_member_id !== member.id;
}

/** "Waiting on you", "Agreed by Jo", "On the company card". The list line. */
export function describeStatus(expense: ExpenseWithNames): string {
  switch (expense.status) {
    case "recorded":
      return "Company card";
    case "submitted":
      return "Waiting to be agreed";
    case "approved":
      return expense.invoice_id
        ? `Credited on a bill · agreed by ${expense.reviewed_by_name ?? "another owner"}`
        : `Agreed by ${expense.reviewed_by_name ?? "another owner"}`;
    case "rejected":
      return `Not agreed by ${expense.reviewed_by_name ?? "another owner"}`;
  }
}
