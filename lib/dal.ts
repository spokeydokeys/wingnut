import "server-only";

import { cache } from "react";
import { redirect } from "next/navigation";

import { createClient } from "./supabase/server";
import type { Database } from "./database.types";

export type Member = Database["public"]["Tables"]["member"]["Row"];

/**
 * The authenticated auth user, or null.
 *
 * Uses getUser(), not getSession(): getSession() only decodes the cookie, which
 * a client controls. getUser() revalidates the token with the auth server.
 *
 * cache() dedupes this within a single render pass. It is a no-op in Server
 * Actions and Route Handlers, so this does hit the network once per call there.
 */
export const verifySession = cache(async () => {
  const supabase = await createClient();
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) return null;
  return data.user;
});

/**
 * The member row for the authenticated user, or null.
 *
 * Signing in does not create a member. claim_member_identity() links the
 * verified auth user to the member row an admin created with that email, and
 * returns null when the email is not on the roster — an authenticated stranger
 * therefore gets no member and no data.
 */
export const getCurrentMember = cache(async (): Promise<Member | null> => {
  const user = await verifySession();
  if (!user) return null;

  const supabase = await createClient();

  const { data: memberId, error: claimError } = await supabase.rpc(
    "claim_member_identity",
  );
  if (claimError || !memberId) return null;

  const { data: member, error } = await supabase
    .from("member")
    .select("*")
    .eq("id", memberId)
    .single();

  if (error) return null;
  return member;
});

/**
 * Use at the top of every protected page, Server Action and Route Handler.
 *
 * Deliberately not called from a layout: layouts do not re-render on
 * navigation, so the session would not be rechecked on a route change, and a
 * layout cannot prevent a child segment from rendering anyway.
 */
export async function requireMember(): Promise<Member> {
  const user = await verifySession();
  if (!user) redirect("/login");

  const member = await getCurrentMember();
  if (!member) redirect("/no-access");

  return member;
}

export async function requireAdmin(): Promise<Member> {
  const member = await requireMember();
  if (member.role !== "admin") redirect("/");
  return member;
}
