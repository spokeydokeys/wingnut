import "server-only";

import { createClient as createSupabaseClient } from "@supabase/supabase-js";

import { supabasePublishableKey, supabaseUrl } from "./env";
import type { Database } from "../database.types";

/**
 * A session-less client for the token-authenticated timer endpoints.
 *
 * The Shortcut presents a bearer token and no cookies, so there is no session
 * to read and nothing to refresh. This client therefore carries the anon role,
 * which can reach exactly two things: `timer_start` and `timer_stop`. Those
 * authenticate the caller from the token hash themselves.
 *
 * Note what this is NOT: a service-role client. A service-role key would
 * bypass every RLS policy in the database, and it would do so for the whole
 * request rather than just the one operation being performed.
 */
export function createTokenClient() {
  return createSupabaseClient<Database>(supabaseUrl(), supabasePublishableKey(), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
