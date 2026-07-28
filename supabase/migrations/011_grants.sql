-- 011 — explicit grants
--
-- REQUIRED because the project was created with "Automatically expose new
-- tables" OFF (the right choice — see below). With auto-expose on, Supabase
-- grants the Data API roles privileges on every new table, which would have
-- handed out access to `kitchen_locations` and `app_secrets` the moment they
-- were created and silently defeated the entire location-privacy model.
--
-- The cost of that correct choice is that nothing is reachable until it is
-- granted here, on purpose, one table at a time. Without this file the app
-- gets "permission denied" on every read.
--
-- RLS still governs WHICH ROWS are visible (010). Grants govern which tables
-- are reachable at all. Both are required; neither substitutes for the other.

set search_path = public, extensions;

grant usage on schema public to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Publicly readable: the discovery surface.
-- ---------------------------------------------------------------------------
grant select on cooks                to anon, authenticated;
grant select on kitchens             to anon, authenticated;
grant select on menu_items           to anon, authenticated;
grant select on serving_sessions     to anon, authenticated;
grant select on enforcement_agencies to anon, authenticated;
grant select on dish_synonyms        to anon, authenticated;
grant select on reviews              to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Signed-in writes. RLS (010) restricts these to the owner or the two parties
-- on a claim; the grant only makes the table addressable.
-- ---------------------------------------------------------------------------
grant update on cooks                        to authenticated;  -- own row only (RLS)
grant insert, update, delete on menu_items   to authenticated;  -- own dishes only (RLS)
grant insert on claims                       to authenticated;  -- status forced to 'pending' (RLS)
grant update on claims                       to authenticated;  -- cook only (RLS)
grant select, insert on claim_items          to authenticated;
grant select on address_disclosures          to authenticated;  -- own disclosures only (RLS)
grant select, insert on complaints           to authenticated;
grant insert on reviews                      to authenticated;  -- completed claims only (RLS)

-- ---------------------------------------------------------------------------
-- Deliberately NOT granted. Listed explicitly so their absence reads as a
-- decision rather than an oversight, and so a reviewer can see the intent.
--
--   kitchen_locations  — home addresses. Reachable only via reveal_address(),
--                        which checks a cook-confirmed claim, rate-limits per
--                        buyer, and writes an audit row.
--   app_secrets        — the geo secret. A GUC was used for this once and
--                        `authenticated` could read it (SPIKE_LOCATION_PRIVACY.md).
--
-- Do not add grants for either. CI fails if you do.
-- ---------------------------------------------------------------------------
revoke all on kitchen_locations from anon, authenticated;
revoke all on app_secrets       from anon, authenticated;

-- Functions are EXECUTE-able by PUBLIC in Postgres by default, so the fuzzing
-- function needs revoking again after any redefinition.
revoke all on function public_point_for(geography, text, double precision) from public, anon, authenticated;
grant execute on function reveal_address(uuid) to authenticated;

-- Future tables inherit nothing. New tables must be granted deliberately,
-- which is the whole point of the setting we chose.
alter default privileges in schema public revoke all on tables from anon, authenticated;
