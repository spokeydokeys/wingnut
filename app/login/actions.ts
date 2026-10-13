"use server";

import { createClient } from "@/lib/supabase/server";

export type LoginState = { error?: string; sentTo?: string };

export async function sendMagicLink(
  _prev: LoginState,
  formData: FormData,
): Promise<LoginState> {
  const email = String(formData.get("email") ?? "")
    .trim()
    .toLowerCase();

  if (!email || !email.includes("@")) {
    return { error: "Enter the email address you were added with." };
  }

  const supabase = await createClient();

  const { error } = await supabase.auth.signInWithOtp({
    email,
    options: {
      // An auth user is created on first sign-in, but that grants nothing on
      // its own: access requires a member row an admin put on the roster with
      // this address. See public.claim_member_identity().
      shouldCreateUser: true,
      emailRedirectTo: `${process.env.NEXT_PUBLIC_SITE_URL}/auth/confirm`,
    },
  });

  if (error) {
    return { error: error.message };
  }

  // Report success regardless of whether the address is on the roster, so this
  // form cannot be used to find out who the owners are.
  return { sentTo: email };
}
