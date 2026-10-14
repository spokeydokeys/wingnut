"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireMember } from "@/lib/dal";
import { getAircraft } from "@/lib/flights";
import { createClient } from "@/lib/supabase/server";
import { deleteReceipt, receiptObjectKey } from "@/lib/storage";

/**
 * Server Actions for receipts.
 *
 * THE IMAGE BYTES DO NOT COME THROUGH HERE. The browser uploads straight to
 * storage with the member's own JWT, and the only thing these actions do about
 * the photo is agree on its key. A phone photo through a Server Action would
 * be a multi-megabyte POST to a serverless function, on dock wifi, with the
 * whole receipt riding on it -- and the bucket's own policies already decide
 * who may write what, so routing the bytes through the server would add a
 * failure mode without adding a check.
 *
 * Hence the three-step flow the capture screen follows:
 *
 *   1. createExpense()   inserts the row and returns its id and the key the
 *                        image belongs at.
 *   2. the browser        uploads the blob to that key.
 *   3. attachReceipt()   points the row at it.
 *
 * The key is derived HERE, from the row that was just written, and never taken
 * from the client. A Server Action is a public POST endpoint; if the key were a
 * parameter, a crafted request could point one expense's `receipt_key` at
 * another's object, and the storage policies would have no way to tell -- they
 * answer "is this object's expense approved?", which is the wrong question if
 * the row is lying about which object is its own.
 *
 * Step 2 failing is a normal outcome, not an error: a receipt with no photo is
 * still a receipt, it just cannot be approved yet. So the row goes in first and
 * the photo catches up, rather than the upload gating the entry.
 *
 * None of these actions decides who may approve or what may change after
 * approval. Those rules are triggers on the table, because this file is a
 * public endpoint and the Studio, the seed and a future importer all write to
 * the same table without passing through it.
 */

type Failed = { error: string };
type Created = { id: string; objectKey: string | null };

const DATE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Dollars and cents, as typed.
 *
 * Tested as text rather than by rounding the parsed number, because
 * `12.34 * 100` is 1233.9999999999998 in binary floating point and a
 * round-trip check on that rejects a perfectly ordinary total. The string
 * either has two decimal places or it does not, and the string is the thing
 * the pilot actually typed.
 */
const MONEY = /^\d+(\.\d{1,2})?$/;

/** One place, so a new screen cannot forget one of the lists. */
function revalidateReceipts() {
  revalidatePath("/", "layout");
}

/**
 * Reads one money field off the form.
 *
 * The total is what is printed on the paper, tax included, and the GST is a
 * part of it rather than on top -- the same rule `expense_gst_within_total`
 * enforces. "12.345" is refused on the screen that typed it rather than
 * silently rounded by Postgres into a figure that no longer matches the paper.
 */
function readAmount(raw: string, label: string): number | Failed {
  const text = raw.trim();
  if (!MONEY.test(text)) {
    return { error: `${label} has to be a number of dollars and cents.` };
  }
  return Number(text);
}

function isFailed(value: unknown): value is Failed {
  return typeof value === "object" && value !== null && "error" in value;
}

/**
 * Enters a receipt.
 *
 * `payer` is the fork the whole table turns on: a member-paid one is
 * `submitted` and will become a credit once somebody else agrees to it, a
 * company-card one is `recorded` and never has an approval path at all. Both
 * states and the status that goes with them are set here from one field,
 * because `expense_status_matches_payer` will refuse any other pairing and a
 * screen that offered one would be offering a save that cannot work.
 *
 * Returns the storage key instead of redirecting, because the caller still has
 * an image to upload and the row it belongs to has only just acquired an id.
 */
export async function createExpense(form: FormData): Promise<Created | Failed> {
  const member = await requireMember();
  const aircraft = await getAircraft();
  if (!aircraft) return { error: "No aircraft has been set up yet." };

  const payer = String(form.get("payer") ?? "member");
  if (payer !== "member" && payer !== "company") {
    return { error: "Say who paid: you, or the company card." };
  }

  const vendor = String(form.get("vendor") ?? "").trim();
  if (vendor === "") return { error: "Say who it was bought from." };

  const spentOn = String(form.get("spent_on") ?? "").trim();
  if (!DATE.test(spentOn)) return { error: "That date could not be read." };

  const total = readAmount(String(form.get("total_amount") ?? ""), "The total");
  if (isFailed(total)) return total;
  if (total <= 0) return { error: "The total has to be more than nothing." };

  const gstRaw = String(form.get("gst_amount") ?? "").trim();
  const gst = gstRaw === "" ? 0 : readAmount(gstRaw, "The GST");
  if (isFailed(gst)) return gst;
  if (gst > total) return { error: "The GST cannot be more than the total." };

  const category = String(form.get("gl_account_code") ?? "").trim();
  if (category === "") return { error: "Pick what it was spent on." };

  // Fuel only, and the reason the Pool page can show cents per litre. Blank is
  // the normal case for everything that is not fuel.
  const litresRaw = String(form.get("litres") ?? "").trim();
  let litres: number | null = null;
  if (litresRaw !== "") {
    litres = Number(litresRaw);
    if (!Number.isFinite(litres) || litres <= 0) {
      return { error: "The litres could not be read." };
    }
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("expense")
    .insert({
      company_id: aircraft.company_id,
      aircraft_id: aircraft.id,
      payer,
      // Nobody is owed anything on a card purchase, so there is nobody to name.
      paid_by_member_id: payer === "member" ? member.id : null,
      vendor,
      spent_on: spentOn,
      total_amount: total,
      gst_amount: gst,
      vendor_gst_number:
        String(form.get("vendor_gst_number") ?? "").trim() || null,
      gl_account_code: category,
      litres,
      note: String(form.get("note") ?? "").trim() || null,
      flight_id: String(form.get("flight_id") ?? "").trim() || null,
      status: payer === "member" ? "submitted" : "recorded",
      submitted_by: member.id,
    })
    .select("id, company_id, spent_on")
    .single();

  if (error || !data) {
    return { error: error?.message ?? "That receipt could not be saved." };
  }

  revalidateReceipts();

  // null when the browser is not sending a photo at all, which is allowed:
  // approval is where the image becomes compulsory, not entry.
  const contentType = String(form.get("content_type") ?? "").trim();
  return {
    id: data.id,
    objectKey: contentType === "" ? null : keyFor(data, contentType),
  };
}

/**
 * Points a row at its image, once the browser has put it there.
 *
 * The key is recomputed from the row rather than accepted as an argument, for
 * the reason in this file's header: the same inputs give the same key, so
 * there is nothing to pass, and a key that came from the client would let one
 * receipt claim another's photo.
 */
export async function attachReceipt(
  expenseId: string,
  contentType: string,
): Promise<Failed | null> {
  await requireMember();

  const supabase = await createClient();
  const { data } = await supabase
    .from("expense")
    .select("id, company_id, spent_on")
    .eq("id", expenseId)
    .maybeSingle();
  if (!data) return { error: "That receipt could not be found." };

  let objectKey: string;
  try {
    objectKey = keyFor(data, contentType);
  } catch {
    return { error: "A receipt has to be a photo." };
  }

  const { error } = await supabase
    .from("expense")
    .update({ receipt_key: objectKey })
    .eq("id", expenseId);
  if (error) return { error: error.message };

  revalidateReceipts();
  return null;
}

function keyFor(
  row: { id: string; company_id: string; spent_on: string },
  contentType: string,
): string {
  return receiptObjectKey({
    companyId: row.company_id,
    spentOn: row.spent_on,
    expenseId: row.id,
    contentType,
  });
}

/**
 * Agrees to a reimbursement.
 *
 * Who agreed is never passed in: `expense_stamp_people` reads it from
 * `current_member_id()` on the transition, which is what stops a crafted
 * request claiming the other owner signed this off. The four-eyes rule and the
 * "no photo, no approval" rule are both in `expense_zz_validate`, so the only
 * thing this sends is the new status.
 *
 * The credit is NOT posted here. It is derived by `month_charges` and written
 * by `close_month`, exactly like a flight charge. A ledger row written at
 * approval would be a second source for the same money and the first re-close
 * would double it.
 */
export async function approveExpense(expenseId: string) {
  await requireMember();

  const supabase = await createClient();
  const { error } = await supabase
    .from("expense")
    .update({ status: "approved" })
    .eq("id", expenseId);
  if (error) throw error;

  revalidateReceipts();
}

/**
 * Declines one, with a reason.
 *
 * A reason is required because the person who is out of pocket has to know
 * what to do next, and "rejected" on its own is the start of an argument
 * rather than the end of one. A rejected receipt is kept, not deleted: it is
 * the record of a decision, and the pilot may well enter a corrected one
 * beside it.
 */
export async function rejectExpense(
  expenseId: string,
  form: FormData,
): Promise<Failed | never> {
  await requireMember();

  const note = String(form.get("review_note") ?? "").trim();
  if (note === "") return { error: "Say why, so it can be put right." };

  const supabase = await createClient();
  const { error } = await supabase
    .from("expense")
    .update({ status: "rejected", review_note: note })
    .eq("id", expenseId);
  if (error) return { error: error.message };

  revalidateReceipts();
  redirect("/receipts");
}

/**
 * Corrects one that has not been agreed yet.
 *
 * Only the fields a mistyped receipt gets wrong. Not the payer and not the
 * status: changing who paid changes which transaction this is, and the way to
 * do that is to delete the receipt and enter the right one.
 *
 * `expense_zz_guard_frozen` refuses this outright once the receipt is approved,
 * or once a company-card one falls in a month that has been billed. The screen
 * hides the form in both cases, but the guard is what makes it true.
 */
export async function updateExpense(
  expenseId: string,
  form: FormData,
): Promise<Failed | never> {
  await requireMember();

  const vendor = String(form.get("vendor") ?? "").trim();
  if (vendor === "") return { error: "Say who it was bought from." };

  const spentOn = String(form.get("spent_on") ?? "").trim();
  if (!DATE.test(spentOn)) return { error: "That date could not be read." };

  const total = readAmount(String(form.get("total_amount") ?? ""), "The total");
  if (isFailed(total)) return total;
  if (total <= 0) return { error: "The total has to be more than nothing." };

  const gstRaw = String(form.get("gst_amount") ?? "").trim();
  const gst = gstRaw === "" ? 0 : readAmount(gstRaw, "The GST");
  if (isFailed(gst)) return gst;
  if (gst > total) return { error: "The GST cannot be more than the total." };

  const category = String(form.get("gl_account_code") ?? "").trim();
  if (category === "") return { error: "Pick what it was spent on." };

  const litresRaw = String(form.get("litres") ?? "").trim();
  let litres: number | null = null;
  if (litresRaw !== "") {
    litres = Number(litresRaw);
    if (!Number.isFinite(litres) || litres <= 0) {
      return { error: "The litres could not be read." };
    }
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("expense")
    .update({
      vendor,
      spent_on: spentOn,
      total_amount: total,
      gst_amount: gst,
      vendor_gst_number:
        String(form.get("vendor_gst_number") ?? "").trim() || null,
      gl_account_code: category,
      litres,
      note: String(form.get("note") ?? "").trim() || null,
    })
    .eq("id", expenseId);

  // Not swallowed. The guards above raise rather than matching no rows, which
  // is the whole reason they are triggers: "it would not save" has to reach the
  // person who typed it, and the message says which rule stopped it.
  if (error) return { error: error.message };

  revalidateReceipts();
  redirect(`/receipts/${expenseId}`);
}

/**
 * Removes one entered by mistake.
 *
 * The image goes first and the row second. The other order would leave an
 * object in the bucket with no row pointing at it -- an orphan nothing in the
 * app can see or reach, which is worse than this order's failure mode, where
 * the delete is simply refused and nothing has changed.
 *
 * Both halves are refused once the receipt is approved: the row by
 * `expense_zz_guard_frozen` and the object by the bucket's
 * `receipt_delete_until_approved`. By then the picture is the evidence behind
 * a credit somebody has agreed to and may already have been invoiced.
 */
export async function deleteExpense(expenseId: string) {
  await requireMember();

  const supabase = await createClient();
  const { data } = await supabase
    .from("expense")
    .select("receipt_key")
    .eq("id", expenseId)
    .maybeSingle();

  if (data?.receipt_key) {
    const { error } = await deleteReceipt(supabase, data.receipt_key);
    if (error) throw new Error(error);
  }

  const { error } = await supabase.from("expense").delete().eq("id", expenseId);
  if (error) throw error;

  revalidateReceipts();
  redirect("/receipts");
}
