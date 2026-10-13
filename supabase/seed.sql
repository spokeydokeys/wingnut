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
-- 2034 prop calendar limit. Those are at the bottom of this file.
--
-- The two snags near the end are invented sample data and should be DELETED
-- rather than corrected -- unlike everything else here, there is no real value
-- they stand in for.
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

-- ---------------------------------------------------------------------------
-- Opening tach datum
--
-- TODO(seed) the real current tach reading, and the date it was read.
--
-- Everything on the maintenance screen is measured from this: with no reading
-- at all, aircraft_tach_estimate returns null and every tach-based item reads
-- "unknown". 500.00 is chosen to make "about 500 of 2000 engine hours used"
-- -- which IS a real fact from the spec -- fall out of an engine datum of zero.
-- ---------------------------------------------------------------------------

insert into public.tach_reading (aircraft_id, reading, read_at, read_by, source, note)
values (
  '00000000-0000-0000-0000-0000000ac001',
  500.00,                                   -- TODO(seed) current tach
  -- Noon in the aeroplane's zone, for the same reason logTachReading uses noon:
  -- a bare date is midnight UTC, which is the afternoon BEFORE in Victoria, so
  -- a reading taken on the 1st would be reported as read on 30 Sept.
  timestamptz '2026-10-01 12:00 America/Vancouver', -- TODO(seed) when it was read
  '00000000-0000-0000-0000-00000000a001',
  'manual',
  'Opening datum, placeholder figure'
);

-- ---------------------------------------------------------------------------
-- The four maintenance items (SPEC.md 4.4)
--
-- The items, their intervals and their bases are real. The dates and tachs of
-- when each was last done are not, and are marked below.
--
-- sort_order follows the wireframe: the things that come due often first, the
-- once-in-a-lifetime limits last.
--
-- The prop overhaul carries a due_date and no interval. It is a calendar limit
-- with no known start, so there is no fraction of its life to draw a bar from,
-- and the screen shows the date instead. Inventing a start just to have a bar
-- would be a made-up number presented as a measurement.
-- ---------------------------------------------------------------------------

insert into public.maintenance_item (
  id, aircraft_id, name, kind, basis,
  interval_hours, interval_months, due_date, lead_hours, lead_days, est_cost, sort_order
) values
  ('00000000-0000-0000-0000-0000000f0001',
   '00000000-0000-0000-0000-0000000ac001',
   'Prop hub grease', 'recurring_task', 'tach',
   25.0, null, null, 3.0, null, null, 1),       -- lead 3 hr: warn at 22 of 25

  ('00000000-0000-0000-0000-0000000f0002',
   '00000000-0000-0000-0000-0000000ac001',
   'Prop blade clip inspection', 'recurring_inspection', 'calendar',
   null, 24, null, null, 60, null, 2),          -- lead 60 days

  ('00000000-0000-0000-0000-0000000f0003',
   '00000000-0000-0000-0000-0000000ac001',
   'Engine overhaul', 'life_limit', 'tach',
   2000.0, null, null, 100.0, null, null, 3),   -- TODO(seed) est_cost

  ('00000000-0000-0000-0000-0000000f0004',
   '00000000-0000-0000-0000-0000000ac001',
   'Prop overhaul', 'life_limit', 'calendar',
   null, null, date '2034-01-01', null, 180, null, 4);  -- TODO(seed) est_cost

-- Last done, as events rather than columns on the item: the newest event IS the
-- counter, so correcting one of these corrects the screen.
--
-- The engine's event is its zero datum -- the tach reading at which the current
-- engine started its life, not a job anyone did on this aeroplane. The prop
-- overhaul has no event at all: it has never been done.
insert into public.maintenance_event (item_id, done_on, tach, done_by, note) values
  ('00000000-0000-0000-0000-0000000f0001',
   date '2026-09-20', 481.00,                 -- TODO(seed) tach at last hub grease
   '00000000-0000-0000-0000-00000000a001', 'Placeholder: last grease'),

  ('00000000-0000-0000-0000-0000000f0002',
   date '2024-11-22', null,                   -- TODO(seed) date of last blade clip inspection
   '00000000-0000-0000-0000-00000000a001', 'Placeholder: last blade clip inspection'),

  ('00000000-0000-0000-0000-0000000f0003',
   date '2015-01-01', 0.00,                   -- TODO(seed) engine zero-time datum
   '00000000-0000-0000-0000-00000000a001', 'Placeholder: engine zero datum');

-- ---------------------------------------------------------------------------
-- Sample snags
--
-- TODO(seed) DELETE these two rows. They are the wireframe's invented examples,
-- here so the Aircraft tab has something to lay out in local development.
-- ---------------------------------------------------------------------------

-- The seep is the one worth re-checking rather than fixing, so it carries the
-- re-check: look at it again next time the prop hub is greased and the cowling
-- is already off. That used to be the whole of its note; it is now a field, and
-- the mark-done screen for the grease says so.
insert into public.snag (
  aircraft_id, title, status, grounding, reported_by, reported_at, notes,
  recheck_item_id
) values
  ('00000000-0000-0000-0000-0000000ac001',
   'Left brake squeals on taxi', 'open', false,
   '00000000-0000-0000-0000-00000000a002', now() - interval '4 days', null,
   null),
  ('00000000-0000-0000-0000-0000000ac001',
   'Oil seep at valve cover', 'watch', false,
   '00000000-0000-0000-0000-00000000a001', now() - interval '21 days', null,
   '00000000-0000-0000-0000-0000000f0001');

-- ---------------------------------------------------------------------------
-- Flights, and the September close
--
-- TODO(seed) DELETE everything below. It is invented, and exists so the Bills
-- tab has a closed month to show history for and an open one to draft.
--
-- Written as literal rows rather than by calling close_month(), because the
-- seed runs with no session and close_month() refuses anyone who is not an
-- admin -- which is the point of it. The figures are what close_month() would
-- produce: 2.3 hr at the opening rate, split across its six components, plus
-- half of each monthly fixed cost.
-- ---------------------------------------------------------------------------

insert into public.invoice
  (id, company_id, member_id, period_month, number, status, issued_at, note)
values
  ('00000000-0000-0000-0000-00000001f001',
   '00000000-0000-0000-0000-00000000c000',
   '00000000-0000-0000-0000-00000000a001',
   date '2026-09-01', 1, 'issued',
   timestamptz '2026-10-01 09:00 America/Vancouver', 'Placeholder: September'),
  ('00000000-0000-0000-0000-00000001f002',
   '00000000-0000-0000-0000-00000000c000',
   '00000000-0000-0000-0000-00000000a002',
   date '2026-09-01', 2, 'issued',
   timestamptz '2026-10-01 09:00 America/Vancouver', 'Placeholder: September');

-- The counter has to be moved past the numbers used above, or the first real
-- close would try to reissue number 1 and hit the unique index.
insert into public.invoice_counter (company_id, next_number)
values ('00000000-0000-0000-0000-00000000c000', 3);

-- ---------------------------------------------------------------------------
-- Places
--
-- Saved places only, by the owner's decision: no OurAirports or OSM import, so
-- the list grows as the aeroplane goes places. Both rows below are 'saved'
-- rather than 'ourairports' for that reason -- the source column records where
-- a row CAME from, and these came from this file.
--
-- TODO(seed) verify the Victoria Harbour coordinates against the Canada Flight
-- Supplement before relying on the 1 km match. It is the one real place in the
-- spec; everything else here is invented and should be deleted rather than
-- corrected.
-- ---------------------------------------------------------------------------

insert into public.place (id, company_id, name, kind, source, lat, lon)
values
  ('00000000-0000-0000-0000-0000000ad001',
   '00000000-0000-0000-0000-00000000c000',
   'Victoria Harbour water aerodrome', 'water_aerodrome', 'saved',
   48.422200, -123.387800),
  ('00000000-0000-0000-0000-0000000ad002',
   '00000000-0000-0000-0000-00000000c000',
   'TODO(seed) Example Bay', 'bay', 'saved',
   48.650000, -123.400000);

-- September's flights, locked to the invoice they were billed on. 1.4 hr and
-- 0.9 hr; billed_hours and est_tach_hours are derived by the trigger.
--
-- journey_text is deliberately left out: the flights name their two ends, and
-- flight_set_journey builds "Victoria Harbour water aerodrome → TODO(seed)
-- Example Bay" from them. Writing the sentence here as well would mean the seed
-- could agree with itself while the trigger was broken.
insert into public.flight
  (aircraft_id, pilot_member_id, status, start_at, end_at, tach_factor_used,
   invoice_id, origin_place_id, dest_place_id)
values
  ('00000000-0000-0000-0000-0000000ac001',
   '00000000-0000-0000-0000-00000000a001', 'billed',
   timestamptz '2026-09-12 10:00 America/Vancouver',
   timestamptz '2026-09-12 11:24 America/Vancouver', 1.300,
   '00000000-0000-0000-0000-00000001f001',
   '00000000-0000-0000-0000-0000000ad001',
   '00000000-0000-0000-0000-0000000ad002'),
  ('00000000-0000-0000-0000-0000000ac001',
   '00000000-0000-0000-0000-00000000a001', 'billed',
   timestamptz '2026-09-26 13:00 America/Vancouver',
   timestamptz '2026-09-26 13:54 America/Vancouver', 1.300,
   '00000000-0000-0000-0000-00000001f001',
   '00000000-0000-0000-0000-0000000ad002',
   '00000000-0000-0000-0000-0000000ad001');

-- October's flight is still confirmed, not billed: the month is open, the
-- flight is still editable, and it is what "October so far" is drafted from.
insert into public.flight
  (aircraft_id, pilot_member_id, status, start_at, end_at, tach_factor_used,
   origin_place_id, dest_place_id)
values
  ('00000000-0000-0000-0000-0000000ac001',
   '00000000-0000-0000-0000-00000000a001', 'confirmed',
   timestamptz '2026-10-05 09:00 America/Vancouver',
   timestamptz '2026-10-05 11:06 America/Vancouver', 1.300,
   '00000000-0000-0000-0000-0000000ad001',
   '00000000-0000-0000-0000-0000000ad001');

-- One line per rate component, because the general ledger wants fuel, reserve
-- and operating revenue in different accounts. The pilot sees them summed.
insert into public.ledger_entry
  (company_id, member_id, invoice_id, kind, entry_date, description,
   quantity, unit_rate, amount, tax_treatment, gl_account_code, recorded_by)
values
  ('00000000-0000-0000-0000-00000000c000', '00000000-0000-0000-0000-00000000a001',
   '00000000-0000-0000-0000-00000001f001', 'flight_charge', date '2026-09-30',
   'Flight time — Fuel',               2.30, 150.0000, 345.00, 'taxable', '4100',
   '00000000-0000-0000-0000-00000000a001'),
  ('00000000-0000-0000-0000-00000000c000', '00000000-0000-0000-0000-00000000a001',
   '00000000-0000-0000-0000-00000001f001', 'flight_charge', date '2026-09-30',
   'Flight time — Engine overhaul',     2.30,  40.0000,  92.00, 'taxable', '4300',
   '00000000-0000-0000-0000-00000000a001'),
  ('00000000-0000-0000-0000-00000000c000', '00000000-0000-0000-0000-00000000a001',
   '00000000-0000-0000-0000-00000001f001', 'flight_charge', date '2026-09-30',
   'Flight time — Propeller',           2.30,  10.0000,  23.00, 'taxable', '4300',
   '00000000-0000-0000-0000-00000000a001'),
  ('00000000-0000-0000-0000-00000000c000', '00000000-0000-0000-0000-00000000a001',
   '00000000-0000-0000-0000-00000001f001', 'flight_charge', date '2026-09-30',
   'Flight time — Floats and rigging',  2.30,  15.0000,  34.50, 'taxable', '4300',
   '00000000-0000-0000-0000-00000000a001'),
  ('00000000-0000-0000-0000-00000000c000', '00000000-0000-0000-0000-00000000a001',
   '00000000-0000-0000-0000-00000001f001', 'flight_charge', date '2026-09-30',
   'Flight time — Contingency',         2.30,  15.0000,  34.50, 'taxable', '4300',
   '00000000-0000-0000-0000-00000000a001'),
  ('00000000-0000-0000-0000-00000000c000', '00000000-0000-0000-0000-00000000a001',
   '00000000-0000-0000-0000-00000001f001', 'flight_charge', date '2026-09-30',
   'Flight time — Other operating',     2.30,  55.0000, 126.50, 'taxable', '4200',
   '00000000-0000-0000-0000-00000000a001'),
  ('00000000-0000-0000-0000-00000000c000', '00000000-0000-0000-0000-00000000a001',
   '00000000-0000-0000-0000-00000001f001', 'hangarage', date '2026-09-30',
   'Hangarage · 50% share',             0.50, 600.0000, 300.00, 'taxable', '4400',
   '00000000-0000-0000-0000-00000000a001'),
  ('00000000-0000-0000-0000-00000000c000', '00000000-0000-0000-0000-00000000a001',
   '00000000-0000-0000-0000-00000001f001', 'insurance', date '2026-09-30',
   'Insurance · 50% share',             0.50, 450.0000, 225.00, 'out_of_scope', '4500',
   '00000000-0000-0000-0000-00000000a001'),

  -- Owner Two did not fly in September, so their bill is the fixed costs only.
  ('00000000-0000-0000-0000-00000000c000', '00000000-0000-0000-0000-00000000a002',
   '00000000-0000-0000-0000-00000001f002', 'hangarage', date '2026-09-30',
   'Hangarage · 50% share',             0.50, 600.0000, 300.00, 'taxable', '4400',
   '00000000-0000-0000-0000-00000000a001'),
  ('00000000-0000-0000-0000-00000000c000', '00000000-0000-0000-0000-00000000a002',
   '00000000-0000-0000-0000-00000001f002', 'insurance', date '2026-09-30',
   'Insurance · 50% share',             0.50, 450.0000, 225.00, 'out_of_scope', '4500',
   '00000000-0000-0000-0000-00000000a001');

-- Recorded by the OTHER owner, which is the rule: with more than one admin, the
-- person whose balance it clears is not the person who confirms it arrived.
insert into public.ledger_entry
  (company_id, member_id, kind, entry_date, description, amount,
   tax_treatment, gl_account_code, recorded_by)
values
  ('00000000-0000-0000-0000-00000000c000', '00000000-0000-0000-0000-00000000a001',
   'payment', date '2026-10-03', 'e-Transfer received', -800.00,
   'out_of_scope', '1000', '00000000-0000-0000-0000-00000000a002');

-- ---------------------------------------------------------------------------
-- Tasks
--
-- The reconcile series is real: it is the thing that reminds an admin to match
-- the coded expenses against the bank, which happens in the general ledger and
-- not in this app. Ten days' grace because the statements have to arrive first.
--
-- The two one-offs below are invented sample data and should be DELETED rather
-- than corrected, like the snags above.
-- ---------------------------------------------------------------------------

insert into public.task_series
  (id, company_id, title, detail, recurrence, due_offset_days, admins_only)
values (
  '00000000-0000-0000-0000-0000000ae001',
  '00000000-0000-0000-0000-00000000c000',
  'Reconcile the bank account',
  'Match every coded expense in Wingnut against what actually cleared the '
  || 'operating account, in the accounting system. Anything on the statement '
  || 'with no receipt in here needs chasing.',
  'month_close', 10, true
);

-- September was reconciled by Owner One, so the rotation says the next one is
-- Owner Two's -- which is the point of seeding a completed one rather than
-- starting from empty.
--
-- task_stamp_completed is disabled for this statement on purpose: it stamps the
-- completion from current_member_id(), and a seed has nobody signed in, so a
-- historical fact cannot be stated any other way.
alter table public.task disable trigger task_stamp_completed;

insert into public.task
  (id, company_id, series_id, period_month, title, assignee_member_id,
   due_date, status, completed_by, completed_at)
values (
  '00000000-0000-0000-0000-0000000af001',
  '00000000-0000-0000-0000-00000000c000',
  '00000000-0000-0000-0000-0000000ae001',
  date '2026-09-01',
  'Reconcile the bank account — Sep 2026',
  '00000000-0000-0000-0000-00000000a001',
  date '2026-10-10',
  'done',
  '00000000-0000-0000-0000-00000000a001',
  timestamptz '2026-10-08 19:40:00-07'
);

alter table public.task enable trigger task_stamp_completed;

insert into public.task
  (id, company_id, title, detail, assignee_member_id, due_date, created_by)
values
  ('00000000-0000-0000-0000-0000000af002',
   '00000000-0000-0000-0000-00000000c000',
   'Ring the hangar owner about the water leak',
   'Drip over the port wing after heavy rain. Ask whether the roof is theirs '
   || 'to fix before we get a quote.',
   '00000000-0000-0000-0000-00000000a002',
   date '2026-10-10',
   '00000000-0000-0000-0000-00000000a001'),
  ('00000000-0000-0000-0000-0000000af003',
   '00000000-0000-0000-0000-00000000c000',
   'Renew the dock licence',
   null,
   '00000000-0000-0000-0000-00000000a001',
   date '2026-11-30',
   '00000000-0000-0000-0000-00000000a001');
