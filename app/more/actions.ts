"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireAdmin } from "@/lib/dal";
import { createClient } from "@/lib/supabase/server";

/**
 * Server Actions for the roster.
 *
 * `member_admin_write` is the rule; requireAdmin here is the courtesy of a
 * redirect instead of a silent refusal. Neither is restated as a role check
 * against the row being written, because a second copy of the rule is a copy
 * that can fall out of step with the policy.
 */

type Failed = { error: string };

const UUID = /^[0-9a-f-]{36}$/i;

/**
 * Change one of the two columns an admin may change about somebody else.
 *
 * Both buttons on the People screen are the same write with a different patch,
 * and both can be refused by the same two rules, so they share this rather
 * than each carrying its own copy of what a refusal means.
 *
 * `member_keeps_an_admin` raises P0001 when the change would empty the roster
 * of active admins. Its message is accurate but is written for whoever reads
 * the logs; the person holding the phone gets told what to do instead.
 */
async function patchMember(
  id: string,
  patch: { role: "pilot" | "admin" } | { is_active: boolean },
): Promise<Failed | null> {
  await requireAdmin();
  if (!UUID.test(id)) return { error: "That person could not be read." };

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("member")
    .update(patch)
    .eq("id", id)
    .select("id")
    .maybeSingle();

  if (error) {
    return {
      error: error.code === "P0001"
        ? "Somebody has to be an admin. Make another person an admin first."
        : error.message,
    };
  }
  // member_admin_write refuses by matching no rows rather than by raising, so
  // an empty result is the refusal -- which here means the admin doing this
  // stopped being one between the screen rendering and the button being hit.
  if (!data) return { error: "That change was refused." };

  revalidatePath("/", "layout");
  return null;
}

/**
 * Give or take away admin.
 *
 * Nothing here checks who is being changed. An admin may demote themselves --
 * that is how a handover ends -- and the only change that is actually
 * impossible is the one that leaves nobody able to do this again, which the
 * database refuses whoever asks.
 */
export async function setRole(
  _prev: Failed | null,
  form: FormData,
): Promise<Failed | null> {
  const role = String(form.get("role") ?? "");
  if (role !== "pilot" && role !== "admin") {
    return { error: "That role could not be read." };
  }

  return patchMember(String(form.get("id") ?? ""), { role });
}

/**
 * Retire somebody, or bring them back.
 *
 * This is the nearest thing to a delete the roster has, and it is not one:
 * every flight, invoice and receipt behind them stays exactly where it is, and
 * `ownership_share.member_id` is `on delete restrict` precisely so that a real
 * delete cannot quietly take a month's billing with it.
 */
export async function setActive(
  _prev: Failed | null,
  form: FormData,
): Promise<Failed | null> {
  return patchMember(String(form.get("id") ?? ""), {
    is_active: String(form.get("is_active") ?? "") === "true",
  });
}

/**
 * Put somebody on the roster.
 *
 * No password, no invitation code and no auth user: `auth_user_id` stays null
 * and the first magic-link sign-in at this exact address claims the row
 * (claim_member_identity). That is why the email is the one field here that
 * cannot be approximately right -- it is the whole of the credential.
 *
 * Everyone starts as a pilot. An admin can pay anybody, close a month and
 * change what the aeroplane costs, so it is a thing to be given deliberately
 * on the screen that lists who has it, rather than a dropdown on a form that
 * is filled in once and quickly.
 */
export async function addPerson(
  _prev: Failed | null,
  form: FormData,
): Promise<Failed | never> {
  await requireAdmin();

  const fullName = String(form.get("full_name") ?? "").trim();
  const email = String(form.get("email") ?? "")
    .trim()
    .toLowerCase();

  if (fullName === "") return { error: "Give them a name." };
  // Deliberately the loosest possible check. The address is proved by the
  // sign-in link arriving, not by a regular expression here, and a pattern
  // strict enough to be worth writing would also refuse somebody's real
  // address one day.
  if (!email.includes("@")) return { error: "That email address is not usable." };

  const supabase = await createClient();
  const { error } = await supabase
    .from("member")
    .insert({ full_name: fullName, email });

  // member_email_lower_key is a unique index on lower(email), so the same
  // person added twice is caught by the database rather than by a lookup
  // here that another admin could race.
  if (error) {
    return {
      error: error.code === "23505"
        ? "Somebody on the roster already has that email address."
        : error.message,
    };
  }

  revalidatePath("/", "layout");
  redirect("/more/people");
}

/**
 * Record a new ownership split, effective from a date.
 *
 * There is no edit and no delete to go with this. `fixed_cost_share` resolves
 * ownership as of the first of each month, so changing a period that has been
 * billed changes what a closed month should have charged -- which SPEC.md 4.6
 * forbids. A correction is a new period, dated when the correction takes
 * effect, and the old one stays as the record of what was actually invoiced.
 *
 * `record_ownership_period` does both inserts in one transaction and is the
 * only reason this is an RPC rather than two `.insert()` calls; see the
 * migration for what a half-written period would do to the billing.
 */
export async function addOwnershipPeriod(
  _prev: Failed | null,
  form: FormData,
): Promise<Failed | never> {
  await requireAdmin();

  const aircraftId = String(form.get("aircraft_id") ?? "");
  const effectiveFrom = String(form.get("effective_from") ?? "");
  if (!UUID.test(aircraftId)) return { error: "That aeroplane could not be read." };
  if (!/^\d{4}-\d{2}-\d{2}$/.test(effectiveFrom)) {
    return { error: "Give the date this split starts from." };
  }

  // One `shares.<member id>` field per person the form offered. Reading them
  // back off the form rather than re-querying the roster means the split that
  // is saved is the one that was on the screen, even if somebody was retired
  // in between.
  const memberIds: string[] = [];
  const shares: number[] = [];
  for (const [key, value] of form.entries()) {
    if (!key.startsWith("shares.")) continue;

    const memberId = key.slice("shares.".length);
    const held = Number(String(value).trim());
    if (!UUID.test(memberId)) return { error: "That person could not be read." };
    if (!Number.isInteger(held) || held < 0) {
      return { error: "Holdings are whole shares, and cannot be negative." };
    }

    memberIds.push(memberId);
    shares.push(held);
  }

  if (memberIds.length === 0) return { error: "Nobody was given a holding." };

  const supabase = await createClient();
  const { error } = await supabase.rpc("record_ownership_period", {
    p_aircraft_id: aircraftId,
    p_effective_from: effectiveFrom,
    p_note: String(form.get("note") ?? ""),
    p_member_ids: memberIds,
    p_shares: shares,
  });

  if (error) {
    // The form cannot offer the same person twice, so the only unique index
    // this can land on is (aircraft_id, effective_from).
    if (error.code === "23505") {
      return { error: "A split already starts on that date. Pick another, or change that one's successor." };
    }
    // Every other refusal here is the function's own, and those are written to
    // be read: "ownership shares sum to 1150, must be 1200" says the number
    // that was typed and the number it had to be, which is the whole of the
    // advice. Rewording it here would only lose the arithmetic.
    return { error: error.message };
  }

  revalidatePath("/", "layout");
  redirect("/more/ownership");
}
