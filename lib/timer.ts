import "server-only";

import { NextResponse } from "next/server";

import { bearerToken, hashApiToken } from "./api-token";
import { createTokenClient } from "./supabase/token-client";

// Shared by /api/timer/start and /api/timer/stop. The two endpoints differ only
// in which function they call, and SPEC.md 7 gives them the same body, so the
// validation and the error mapping are written once.

type TimerAction = "timer_start" | "timer_stop";

// The timer functions raise with explicit SQLSTATEs, which makes this mapping a
// contract rather than string-matching on messages.
const STATUS_BY_SQLSTATE: Record<string, number> = {
  "28000": 401, // invalid_authorization_specification -- unknown/revoked token
  "42501": 403, // insufficient_privilege -- another pilot's running flight
  "55006": 409, // object_in_use -- already running, or not running
};

class BadRequest extends Error {}

// Absent arguments are `undefined` rather than `null` so they drop out of the
// JSON body entirely and Postgres applies the function's own defaults.

function optionalNumber(
  body: Record<string, unknown>,
  key: string,
  min: number,
  max: number,
): number | undefined {
  const raw = body[key];
  if (raw === undefined || raw === null || raw === "") return undefined;

  // Shortcuts send numbers as strings often enough that rejecting them would
  // be hostile, but anything non-numeric is a mistake worth reporting.
  const value = typeof raw === "string" ? Number(raw) : raw;
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new BadRequest(`${key} must be a number`);
  }
  if (value < min || value > max) {
    throw new BadRequest(`${key} must be between ${min} and ${max}`);
  }
  return value;
}

function optionalString(
  body: Record<string, unknown>,
  key: string,
  maxLength: number,
): string | undefined {
  const raw = body[key];
  if (raw === undefined || raw === null || raw === "") return undefined;
  if (typeof raw !== "string") throw new BadRequest(`${key} must be a string`);
  if (raw.length > maxLength) {
    throw new BadRequest(`${key} must be at most ${maxLength} characters`);
  }
  return raw;
}

export async function handleTimerRequest(request: Request, action: TimerAction) {
  const token = bearerToken(request);
  if (!token) {
    return NextResponse.json(
      { error: "missing bearer token" },
      { status: 401, headers: { "www-authenticate": "Bearer" } },
    );
  }

  let body: Record<string, unknown> = {};
  if (request.headers.get("content-length") !== "0") {
    try {
      const parsed = await request.json();
      // A JSON body that is not an object (a bare array or string) is a mistake.
      if (parsed !== null && typeof parsed === "object" && !Array.isArray(parsed)) {
        body = parsed as Record<string, unknown>;
      }
    } catch {
      // No body at all is fine: starting a flight without a GPS fix is a
      // supported case (SPEC.md 4.2, "indoors, permission denied").
    }
  }

  let args;
  try {
    args = {
      p_token_hash: hashApiToken(token),
      p_lat: optionalNumber(body, "lat", -90, 90),
      p_lon: optionalNumber(body, "lon", -180, 180),
      p_accuracy_m: optionalNumber(body, "accuracy", 0, 100_000),
      p_idempotency_key: optionalString(body, "idempotency_key", 200),
      p_aircraft_id: optionalString(body, "aircraft_id", 36),
    };
  } catch (error) {
    if (error instanceof BadRequest) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    throw error;
  }

  // A fix is only meaningful with both halves; one without the other is a bug
  // in the caller worth surfacing rather than silently dropping.
  if ((args.p_lat === undefined) !== (args.p_lon === undefined)) {
    return NextResponse.json(
      { error: "lat and lon must be given together" },
      { status: 400 },
    );
  }

  const supabase = createTokenClient();
  const { data, error } = await supabase.rpc(action, args);

  if (error) {
    const status = STATUS_BY_SQLSTATE[error.code ?? ""] ?? 500;
    // Only the database's own messages are returned, and they are written for
    // the pilot ("the timer is already running for Owner One").
    return NextResponse.json(
      { error: status === 500 ? "could not update the timer" : error.message },
      { status },
    );
  }

  const flight = Array.isArray(data) ? data[0] : data;
  if (!flight) {
    return NextResponse.json({ error: "could not update the timer" }, { status: 500 });
  }

  return NextResponse.json({
    flight_id: flight.id,
    status: flight.status,
    start_at: flight.start_at,
    end_at: flight.end_at,
    flight_hours: flight.flight_hours,
    billed_hours: flight.billed_hours,
    est_tach_hours: flight.est_tach_hours,
  });
}
