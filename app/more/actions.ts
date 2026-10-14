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
