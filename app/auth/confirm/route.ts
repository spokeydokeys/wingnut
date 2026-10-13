import { redirect } from "next/navigation";
import type { EmailOtpType } from "@supabase/supabase-js";

import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

/**
 * Where the magic link lands. Exchanges the one-time token hash from the email
 * for a session, which @supabase/ssr writes as httpOnly cookies — so the
 * session is readable on the server, unlike the auth server's default flow
 * which returns it in a URL fragment.
 *
 * No `next` / `redirect_to` parameter is accepted on purpose: taking a
 * redirect target from the link would make this an open redirect.
 */
export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const tokenHash = searchParams.get("token_hash");
  const type = searchParams.get("type") as EmailOtpType | null;

  if (!tokenHash || !type) {
    redirect("/login?error=link_invalid");
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.verifyOtp({
    type,
    token_hash: tokenHash,
  });

  if (error) {
    redirect("/login?error=link_expired");
  }

  redirect("/");
}
