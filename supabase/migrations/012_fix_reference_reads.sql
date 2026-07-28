-- 012 — two gaps found by the first live client connection
--
-- Neither was visible from reading the schema. Both needed something to
-- actually connect over the API, which is the argument for the connectivity
-- tests existing at all.
--
-- ---------------------------------------------------------------------------
-- 1. Reference tables were granted but returned zero rows.
--
-- The project has "Enable automatic RLS" on — an event trigger that enables
-- RLS on every new table in `public`. That is the setting we wanted (a table
-- someone adds later starts closed, not open), and this is its documented
-- cost: RLS on + no policy = every row filtered out, with no error.
--
-- `enforcement_agencies` and `dish_synonyms` are reference data — the agency
-- names printed on MEHKO listings, and the bilingual synonym table behind
-- search. They are public by design and were never given policies, because
-- 010 only covered tables holding user data.
--
-- Fails loudly rather than quietly: an empty synonym table degrades search to
-- monolingual matching, which would have looked like a ranking problem for
-- weeks rather than a permissions one.
-- ---------------------------------------------------------------------------

set search_path = public, extensions;

create policy agencies_public_read on enforcement_agencies for select using (true);
create policy synonyms_public_read on dish_synonyms       for select using (true);

-- ---------------------------------------------------------------------------
-- 2. `claims` had INSERT and UPDATE but no SELECT.
--
-- 011 granted the write paths and missed the read, so RLS policy
-- `claims_parties_read` had nothing to act on: a buyer could create a claim
-- and then not see it, and a cook's inbox would have come back empty.
--
-- The grant makes the table addressable; the policy still restricts rows to
-- the two parties on the claim. Both are required.
-- ---------------------------------------------------------------------------

grant select on claims to authenticated;
