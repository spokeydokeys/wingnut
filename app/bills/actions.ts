"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireAdmin } from "@/lib/dal";
import { getAircraft } from "@/lib/flights";
import { createClient } from "@/lib/supabase/server";

/**
 * Server Actions for the admin end of the Bills tab.
 *
 * All three are thin: the arithmetic and every rule worth having live in
 * `close_month`, `issue_invoice` and `record_payment`, which are the authority
 * because a Server Action is a public POST endpoint and these are not the only
 * thing that could ever call them. What is left here is reading what a human
 * typed and putting the database's refusal back in front of them.
 *
 * requireAdmin() is still first in each, so a pilot gets a redirect rather than
 * a raised exception -- but it is the belt, not the braces.
 */

type Failed = { error: string };

/** `2026-09` from a month input, as the first of that month. */
function readMonth(raw: FormDataEntryValue | null): string | null {
  const text = String(raw ?? "");
  return /^\d{4}-\d{2}$/.test(text) ? `${text}-01` : null;
}

/**
 * Build this month's drafts (SPEC.md 4.6: "closing a month locks that month's
 * flights and generates the invoice").
 *
 * Only the drafts. The lock comes with issuing, because a draft is a proposal
 * and an admin who builds one must be able to throw it away and rebuild it
 * after correcting a flight.
 */
export async function closeMonth(
  _prev: Failed | null,
  form: FormData,
): Promise<Failed | never> {
  await requireAdmin();

  const month = readMonth(form.get("month"));
  if (!month) return { error: "That month could not be read." };

  const aircraft = await getAircraft();
  if (!aircraft) return { error: "No aircraft has been set up yet." };

  const supabase = await createClient();
  const { error } = await supabase.rpc("close_month", {
    p_aircraft_id: aircraft.id,
    p_month: month,
  });
  if (error) return { error: error.message };

  revalidatePath("/bills", "layout");
  redirect(`/bills/close?month=${month.slice(0, 7)}`);
}

/** Give a draft its number and lock the flights behind it. */
export async function issueInvoice(
  _prev: Failed | null,
  form: FormData,
): Promise<Failed | never> {
  await requireAdmin();

  const id = String(form.get("invoice_id") ?? "");
  const month = readMonth(form.get("month"));

  const supabase = await createClient();
  const { error } = await supabase.rpc("issue_invoice", { p_invoice_id: id });
  if (error) return { error: error.message };

  revalidatePath("/bills", "layout");
  redirect(month ? `/bills/close?month=${month.slice(0, 7)}` : "/bills/close");
}

/**
 * Record a payment that arrived by e-Transfer.
 *
 * The amount is typed in as the positive figure on the bank statement;
 * `record_payment` negates it, because the sign convention is the ledger's
 * business and not something to get wrong while reading a cheque.
 *
 * Who may record it is the owners' rule -- another admin, when there is more
 * than one admin -- and it is `guard_payment_four_eyes` that enforces it. The
 * picker on the screen simply does not offer the caller their own name, so the
 * refusal is somewhere nobody normally goes.
 */
export async function recordPayment(
  _prev: Failed | null,
  form: FormData,
): Promise<Failed | never> {
  await requireAdmin();

  const memberId = String(form.get("member_id") ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(memberId)) {
    return { error: "Say who the payment came from." };
  }

  const amount = Number(String(form.get("amount") ?? "").trim());
  if (!Number.isFinite(amount) || amount <= 0) {
    return { error: "The amount has to be a positive number." };
  }

  const paidOn = String(form.get("paid_on") ?? "");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(paidOn)) {
    return { error: "That date could not be read." };
  }

  const note = String(form.get("note") ?? "").trim();

  const supabase = await createClient();
  const { error } = await supabase.rpc("record_payment", {
    p_member_id: memberId,
    p_amount: amount,
    p_paid_on: paidOn,
    ...(note ? { p_note: note } : {}),
  });
  if (error) return { error: error.message };

  revalidatePath("/bills", "layout");
  redirect("/bills/close");
}
