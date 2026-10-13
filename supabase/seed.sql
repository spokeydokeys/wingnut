-- Local development seed. Runs on `supabase db reset` only; it is never applied
-- to a hosted project.
--
-- =============================================================================
-- PLACEHOLDERS -- every value marked TODO(seed) below is invented and must be
-- replaced with real figures before the first real invoice is issued. These map
-- to the outstanding items in SPEC.md section 8 question 6.
--
--   - current tach reading
--   - date of last prop blade clip inspection
--   - tach at last prop hub grease
--   - engine and prop overhaul cost estimates
--   - expected hours per year
--   - current wet rate and its components
--   - monthly hangarage and insurance amounts
--   - company legal name, GST registration status and number
--   - e-Transfer recipient address
--
-- Real facts carried over from the spec: the tach factor direction (divide),
-- the four maintenance items, roughly 500 of 2000 engine hours used, and the
-- 2034 prop calendar limit. Those arrive with the maintenance migration.
-- =============================================================================

-- Fixed UUIDs so local data is stable across resets and easy to reference.
--
-- auth_user_id is deliberately left null on both members, exactly as it is in
-- production: an admin puts a person on the roster by email, and the first
-- magic-link sign-in claims the row (public.claim_member_identity). Pre-linking
-- here would mean local dev never exercises that path. Sign in locally with
-- either email below and read the link out of Mailpit on port 54324.

insert into public.company (id, legal_name, gst_registered, gst_number, fiscal_year_end_month, etransfer_recipient)
values (
  '00000000-0000-0000-0000-00000000c000',
  'TODO(seed) Holding Co Ltd.',
  false,            -- TODO(seed) SPEC.md section 8 question 5
  null,             -- TODO(seed) required on invoices once GST registered
  12,               -- TODO(seed) confirm fiscal year end
  null              -- TODO(seed) e-Transfer recipient address
);

insert into public.member (id, full_name, email, role) values
  ('00000000-0000-0000-0000-00000000a001',
   'TODO(seed) Owner One', 'owner1@example.test', 'admin'),
  ('00000000-0000-0000-0000-00000000a002',
   'TODO(seed) Owner Two', 'owner2@example.test', 'admin');

insert into public.aircraft (
  id, company_id, registration, nickname,
  billing_basis, tach_factor, expected_hours_per_year,
  fixed_cost_split, billed_hour_rounding, expense_approval_rule,
  place_match_radius_m
) values (
  '00000000-0000-0000-0000-0000000ac001',
  '00000000-0000-0000-0000-00000000c000',
  'C-XXXX',         -- TODO(seed) real registration
  null,
  'flight_time',
  1.300,            -- confirmed: estimated tach = flight time / 1.3
  100.0,            -- TODO(seed) expected hours per year, drives calendar accrual
  'ownership_pct',  -- confirmed: fixed costs split by ownership percent
  'round_up_tenth', -- confirmed: billed hours round up to 0.1 hr
  'any_other_owner',
  1000              -- 1 km place match radius, spec 4.2
);

-- Opening ownership: two owners at 50/50. When the two prospective owners join,
-- insert a NEW ownership_period with all four shares rather than editing this
-- one, so previously closed months keep billing at the old split.
insert into public.ownership_period (id, aircraft_id, effective_from, note)
values (
  '00000000-0000-0000-0000-0000000b0001',
  '00000000-0000-0000-0000-0000000ac001',
  date '2026-01-01',
  'Opening ownership, two co-owners'
);

insert into public.ownership_share (period_id, member_id, pct) values
  ('00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-00000000a001', 50.0000),
  ('00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-00000000a002', 50.0000);
