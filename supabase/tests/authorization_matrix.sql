-- Authorization test matrix
--
-- ⚠ STATUS: NEVER RUN. This is a specification, not coverage. It requires
-- pgTAP and a fixtures.sql that does not exist yet. Do not treat any area
-- below as verified until this runs green in CI. See ./README.md.
--
-- The location-privacy invariants ARE verified today, in
-- .github/workflows/ci.yml, against a real PostGIS database.
--
-- Written BEFORE the features, because the leak we already shipped in draft was
-- a policy that looked correct in isolation and was defeated by permissive
-- policy OR-composition. A single passing case is not evidence.
--
-- Run with pgTAP: supabase test db
--
-- Matrix: {anon, buyer-no-claim, buyer-pending-claim, buyer-confirmed-claim,
--          other cook, owning cook, admin}
--       × {kitchens, kitchen_locations, reveal_address, claims update}

begin;
select plan(22);

-- ---------------------------------------------------------------------------
-- kitchen_locations is unreachable by every client role. This is the one that
-- matters most: a leak here is a physical-safety incident.
-- ---------------------------------------------------------------------------
set local role anon;
select throws_ok(
  'select * from kitchen_locations',
  '42501',
  null,
  'anon cannot read kitchen_locations'
);

set local role authenticated;
select throws_ok(
  'select * from kitchen_locations',
  '42501',
  null,
  'authenticated cannot read kitchen_locations'
);

select throws_ok(
  'select exact_point from kitchen_locations limit 1',
  '42501',
  null,
  'no column-level path into exact coordinates either'
);

-- ---------------------------------------------------------------------------
-- kitchens exposes public geometry only — assert the column does not exist,
-- so a future migration that "helpfully" adds it back fails loudly here.
-- ---------------------------------------------------------------------------
select hasnt_column('public', 'kitchens', 'exact_point',
  'kitchens must never carry an exact point');
select has_column('public', 'kitchens', 'public_point',
  'kitchens carries the grid-snapped point');

-- ---------------------------------------------------------------------------
-- Fuzzing properties: deterministic, lossy, and independent of the public id.
-- ---------------------------------------------------------------------------
select is(
  public_point_for(ST_MakePoint(-117.89, 34.09)::geography, 'secret-a')::text,
  public_point_for(ST_MakePoint(-117.89, 34.09)::geography, 'secret-a')::text,
  'same input and secret produce a stable point (no averaging attack)'
);

select isnt(
  public_point_for(ST_MakePoint(-117.89, 34.09)::geography, 'secret-a')::text,
  public_point_for(ST_MakePoint(-117.89, 34.09)::geography, 'secret-b')::text,
  'the secret actually keys the grid'
);

-- Lossiness — the actual privacy guarantee.
--
-- Deliberately an AGGREGATE ratio, not a two-point comparison. A pair test is
-- flaky by construction: adjacent points straddle a cell boundary depending on
-- the secret-derived grid phase, and during the spike the same pair failed
-- under one secret and passed under another.
select cmp_ok(
  (select count(*)::numeric / nullif(count(distinct public_point_for(p,'secret-a')::text),0)
     from (select ST_MakePoint(-117.8903 + (i%50)*0.00035,
                                34.0900 + (i/50)*0.0003)::geography as p
           from generate_series(0,2499) i) pts),
  '>=', 20::numeric,
  'homes collapse onto shared published points (measures ~100:1)'
);

select cmp_ok(
  ST_Distance(
    ST_MakePoint(-117.89, 34.09)::geography,
    public_point_for(ST_MakePoint(-117.89, 34.09)::geography, 'secret-a')
  ),
  '<', 320.0,
  'displacement stays within the cell half-diagonal (~283m for a 400m cell)'
);

-- ---------------------------------------------------------------------------
-- A buyer may not promote their own claim.
-- ---------------------------------------------------------------------------
-- setup: seed a cook, kitchen, session, and a pending claim as the buyer
-- (fixtures omitted here; see supabase/tests/fixtures.sql)

select throws_ok(
  $$ update claims set status = 'confirmed' where buyer_id = auth.uid() $$,
  null, null,
  'buyer cannot confirm their own claim'
);

select lives_ok(
  $$ insert into claims (cook_id, serving_session_id, buyer_id, status)
     values (current_setting('test.cook')::uuid,
             current_setting('test.session')::uuid,
             auth.uid(), 'pending') $$,
  'buyer can create a pending claim'
);

select throws_ok(
  $$ insert into claims (cook_id, serving_session_id, buyer_id, status)
     values (current_setting('test.cook')::uuid,
             current_setting('test.session')::uuid,
             auth.uid(), 'confirmed') $$,
  null, null,
  'buyer cannot create a pre-confirmed claim'
);

-- ---------------------------------------------------------------------------
-- reveal_address gating.
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ select reveal_address(current_setting('test.pending_claim')::uuid) $$,
  '42501', null,
  'pending claim does not unlock an address'
);

select throws_ok(
  $$ select reveal_address(current_setting('test.other_claim')::uuid) $$,
  '42501', null,
  'a claim belonging to someone else does not unlock an address'
);

select lives_ok(
  $$ select reveal_address(current_setting('test.confirmed_claim')::uuid) $$,
  'cook-confirmed claim unlocks the address'
);

select is(
  (select count(*)::int from address_disclosures
    where claim_id = current_setting('test.confirmed_claim')::uuid),
  1,
  'every disclosure writes exactly one audit row'
);

-- Rate limit.
select throws_ok(
  $$ select reveal_address(current_setting('test.sixth_claim')::uuid) $$,
  'P0001', null,
  'the sixth distinct kitchen in 24h is refused'
);

-- ---------------------------------------------------------------------------
-- Decay ladder boundaries — mirrored in FreshnessTierTests.swift.
-- ---------------------------------------------------------------------------
select is(freshness_of(now() - interval '1 hour', null), 'lit'::freshness_tier,
  '1h is lit');
select is(freshness_of(now() - interval '4 hours', null), 'dimming'::freshness_tier,
  '4h exactly is dimming');
select is(freshness_of(now() - interval '6 hours', null), 'unconfirmed'::freshness_tier,
  '6h exactly is unconfirmed');
select is(freshness_of(now(), now()), 'out'::freshness_tier,
  'a closed session is out regardless of confirmation age');

-- ---------------------------------------------------------------------------
-- One open session per cook.
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ insert into serving_sessions (cook_id, kitchen_id)
     values (current_setting('test.cook')::uuid,
             current_setting('test.kitchen')::uuid) $$,
  '23505', null,
  'a cook cannot have two open sessions'
);

select * from finish();
rollback;
