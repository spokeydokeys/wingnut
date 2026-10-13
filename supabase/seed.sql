-- Local development seed. Runs on `supabase db reset` only; it is never applied
-- to a hosted project.
--
-- =============================================================================
-- PLACEHOLDERS -- every value marked TODO(seed) below is invented and must be
-- replaced with real figures before the first real invoice is issued. These map
-- to the outstanding items in SPEC.md section 8 question 6.
--
--   - the real chart of accounts codes (every code below is invented)
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

-- ---------------------------------------------------------------------------
-- Chart of accounts
--
-- TODO(seed) Every code here is invented. They must be replaced with the real
-- codes from whatever QBO/Xero file the accountant sets up, or the journal
-- export will not import. Only the shape is meant to be right.
--
-- Note the reserve account is REVENUE, not an expense. CRA generally
-- disallows deducting a contingent reserve, so accruing $40/hr toward an
-- overhaul is very likely income with the cash restricted, not a deduction.
-- The app's reserve is a management construct. An accountant must confirm
-- this before the first T2.
-- ---------------------------------------------------------------------------

insert into public.gl_account (company_id, code, name, type) values
  ('00000000-0000-0000-0000-00000000c000', '1100', 'Accounts receivable - owners', 'asset'),
  ('00000000-0000-0000-0000-00000000c000', '1000', 'Operating bank account',       'asset'),
  ('00000000-0000-0000-0000-00000000c000', '1050', 'Reserve bank account',         'asset'),
  ('00000000-0000-0000-0000-00000000c000', '4100', 'Flight revenue - fuel',        'revenue'),
  ('00000000-0000-0000-0000-00000000c000', '4200', 'Flight revenue - operating',   'revenue'),
  ('00000000-0000-0000-0000-00000000c000', '4300', 'Reserve contributions',        'revenue'),
  ('00000000-0000-0000-0000-00000000c000', '4400', 'Hangarage recovery',           'revenue'),
  ('00000000-0000-0000-0000-00000000c000', '4500', 'Insurance recovery',           'revenue'),
  ('00000000-0000-0000-0000-00000000c000', '5100', 'Fuel',                         'expense'),
  ('00000000-0000-0000-0000-00000000c000', '5200', 'Maintenance',                  'expense'),
  ('00000000-0000-0000-0000-00000000c000', '5300', 'Consumables',                  'expense'),
  ('00000000-0000-0000-0000-00000000c000', '5900', 'Other operating',              'expense');

update public.company
   set ar_account_code   = '1100',
       bank_account_code = '1000'
 where id = '00000000-0000-0000-0000-00000000c000';

-- ---------------------------------------------------------------------------
-- Opening rate schedule
--
-- TODO(seed) SPEC.md section 8 question 6: the real wet rate and how it splits
-- between fuel, reserve and operating. These numbers are invented and sum to
-- $285/hr only so the draft-invoice maths has something to chew on.
--
-- Raising the rate means inserting a NEW rate_schedule with a later
-- effective_from, never editing these rows.
-- ---------------------------------------------------------------------------

insert into public.rate_schedule (id, aircraft_id, effective_from, note)
values (
  '00000000-0000-0000-0000-0000000d0001',
  '00000000-0000-0000-0000-0000000ac001',
  date '2026-01-01',
  'Opening rate, invented placeholder figures'
);

insert into public.rate_component
  (schedule_id, name, kind, rate_per_hour, gl_account_code, tax_treatment, sort_order) values
  ('00000000-0000-0000-0000-0000000d0001', 'Fuel',              'fuel',      150.0000, '4100', 'taxable', 1),
  ('00000000-0000-0000-0000-0000000d0001', 'Engine overhaul',   'reserve',    40.0000, '4300', 'taxable', 2),
  ('00000000-0000-0000-0000-0000000d0001', 'Propeller',         'reserve',    10.0000, '4300', 'taxable', 3),
  ('00000000-0000-0000-0000-0000000d0001', 'Floats and rigging','reserve',    15.0000, '4300', 'taxable', 4),
  ('00000000-0000-0000-0000-0000000d0001', 'Contingency',       'reserve',    15.0000, '4300', 'taxable', 5),
  ('00000000-0000-0000-0000-0000000d0001', 'Other operating',   'operating',  55.0000, '4200', 'taxable', 6);

-- ---------------------------------------------------------------------------
-- Opening fixed costs
--
-- TODO(seed) real monthly hangarage and insurance. Split by ownership percent
-- per the aircraft's fixed_cost_split setting.
-- ---------------------------------------------------------------------------

insert into public.fixed_cost_schedule (id, aircraft_id, effective_from, note)
values (
  '00000000-0000-0000-0000-0000000e0001',
  '00000000-0000-0000-0000-0000000ac001',
  date '2026-01-01',
  'Opening fixed costs, invented placeholder figures'
);

insert into public.fixed_cost
  (schedule_id, name, kind, monthly_amount, gl_account_code, tax_treatment, sort_order) values
  ('00000000-0000-0000-0000-0000000e0001', 'Hangarage', 'hangarage', 600.00, '4400', 'taxable',      1),
  ('00000000-0000-0000-0000-0000000e0001', 'Insurance', 'insurance', 450.00, '4500', 'out_of_scope', 2);
