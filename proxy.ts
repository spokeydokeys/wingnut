import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";

/**
 * Next 16 renamed middleware.ts to proxy.ts and `middleware()` to `proxy()`.
 *
 * This does two jobs, neither of which is authorisation:
 *
 *  1. Refreshes the Supabase session cookie. Server Components cannot write
 *     cookies, so without this a token that expires mid-session is never
 *     renewed and the user is silently logged out.
 *  2. Bounces obviously-anonymous requests to /login so they do not pay for a
 *     render. This is an optimistic check only — the Next docs are explicit
 *     that the proxy "should not be used as a full session management or
 *     authorization solution". The real check is requireMember() in the DAL,
 *     called per page and per action.
 */
export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          for (const { name, value } of cookiesToSet) {
            request.cookies.set(name, value);
          }
          response = NextResponse.next({ request });
          for (const { name, value, options } of cookiesToSet) {
            response.cookies.set(name, value, options);
          }
        },
      },
    },
  );

  // Must be getUser(), not getSession(): this call is what refreshes the token.
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { pathname } = request.nextUrl;
  const isPublic =
    pathname === "/login" ||
    pathname === "/no-access" ||
    pathname.startsWith("/auth/");

  if (!user && !isPublic) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.search = "";
    return NextResponse.redirect(url);
  }

  // Returning `response`, not a fresh one, is what carries any refreshed
  // cookies back to the browser.
  return response;
}

export const config = {
  matcher: [
    // Everything except Next's own assets and static files. The timer API is
    // included on purpose: iOS Shortcuts authenticate with a bearer token, and
    // its route handlers do their own check.
    "/((?!_next/static|_next/image|favicon.ico|manifest.webmanifest|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)",
  ],
};
