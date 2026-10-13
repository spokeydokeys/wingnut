import "server-only";

import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";

import { supabasePublishableKey, supabaseUrl } from "./env";
import type { Database } from "../database.types";

// Next 16: cookies() is async. The sync form was removed.
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient<Database>(supabaseUrl(), supabasePublishableKey(), {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        // Server Components cannot set cookies. Supabase calls this whenever it
        // refreshes a token, so swallowing the failure is expected rather than
        // exceptional: the route handler and the proxy both can write, and one
        // of them will persist the refreshed session.
        try {
          for (const { name, value, options } of cookiesToSet) {
            cookieStore.set(name, value, options);
          }
        } catch {
          // read-only cookie store
        }
      },
    },
  });
}
