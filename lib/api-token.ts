import "server-only";

import { createHash, randomBytes } from "node:crypto";

// Tokens for the iOS Shortcut that starts and stops the timer (SPEC.md 7).
//
// Plain SHA-256 is the right hash here, which is worth saying because it is
// normally the wrong answer. A slow hash (bcrypt, argon2) exists to make
// guessing a LOW-entropy human password expensive. These tokens are 32 bytes
// from a CSPRNG, so there is nothing to guess and a slow hash would only make
// every timer call slower.
//
// The prefix is there so a leaked token is recognisable in a log or a paste and
// can be revoked, and so secret scanners have something to match on.
const TOKEN_BYTES = 32;
const TOKEN_PREFIX = "wingnut_";

export function hashApiToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

/**
 * Returns the token to show the owner exactly once, and the hash to store.
 * The plaintext is deliberately not persisted anywhere.
 */
export function generateApiToken(): { token: string; hash: string } {
  const token = TOKEN_PREFIX + randomBytes(TOKEN_BYTES).toString("base64url");
  return { token, hash: hashApiToken(token) };
}

/** Pulls the token out of an `Authorization: Bearer ...` header. */
export function bearerToken(request: Request): string | null {
  const header = request.headers.get("authorization");
  if (!header) return null;

  const [scheme, ...rest] = header.split(" ");
  if (scheme.toLowerCase() !== "bearer") return null;

  const token = rest.join(" ").trim();
  return token.length > 0 ? token : null;
}
