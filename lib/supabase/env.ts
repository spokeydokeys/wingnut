// Read the Supabase config once, loudly. A missing publishable key otherwise
// surfaces as a confusing 401 from the auth endpoint at sign-in time.
//
// The values are passed in as literal `process.env.NEXT_PUBLIC_…` expressions
// rather than looked up by name inside `required`. That is not a style
// preference: the bundler replaces NEXT_PUBLIC_ reads with their values by
// scanning for exactly that syntax, so `process.env[name]` is left alone and
// reads as undefined in the browser. On the server both forms work, which is
// what made this survive until the first client-side upload.
function required(name: string, value: string | undefined): string {
  if (!value) {
    throw new Error(`${name} is not set. Copy .env.example to .env.local.`);
  }
  return value;
}

export const supabaseUrl = () =>
  required("NEXT_PUBLIC_SUPABASE_URL", process.env.NEXT_PUBLIC_SUPABASE_URL);

export const supabasePublishableKey = () =>
  required(
    "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  );
