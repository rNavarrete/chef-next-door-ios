-- Empty this database of everything a person made, and nothing else.
--
-- Run ONCE, against the project that is becoming production, before any real
-- user touches it. `lit-kitchen` (niehxlaegsuhdqbyikut) spent its first days as
-- the only environment: it carries the demo cooks used to build the feed, the
-- accounts QA created, a kitchen called "QA Tester" that was lit in the live
-- feed, and photos uploaded to exercise the four-slot picker. None of that
-- should greet the first real cook.
--
-- ## NOT a migration, deliberately
--
-- This lives outside supabase/migrations because migrations run against every
-- environment, forever. As a migration this would wipe the new staging project
-- on its first `db push`, and every environment created after it. It is a
-- one-off operation on one database, so it is a script you run on purpose.
--
-- ## What it does not touch, and why "wipe everything" cannot be literal
--
--   enforcement_agencies (4 rows)
--     Which health department covers which city, and whether that agency has
--     opted into MEHKO. `agency_for_city` reads it during registration. Empty
--     it and `register_cook` has no agency to attach a kitchen to — nobody can
--     open a kitchen anywhere, and the error will not say why.
--
--   permit_registry (382 rows)
--     LA County's published MEHKO register, mirrored. `preflight_permit` and
--     `verify_permit` both check against it. Empty it and every permit number
--     a cook types comes back `not_found` — which, since 062, blocks them from
--     finishing registration. The gate built to keep out unverifiable permits
--     would keep out all of them.
--
-- Both are public reference data, not anyone's content. Neither is regenerated
-- by a migration; permit_registry is refilled only by fetching the county JSON
-- and calling refresh_permit_registry().
--
-- ## Storage is NOT handled here
--
-- `delete from storage.objects` is refused by Supabase's own trigger:
--
--   42501: Direct deletion from storage tables is not allowed.
--          Use the Storage API instead.
--   HINT:  This prevents accidental data loss from orphaned objects.
--
-- Which is the right call — deleting the metadata row would strand the bytes in
-- the bucket with nothing left pointing at them. The buckets are emptied
-- separately, through the API:
--
--   npx supabase storage rm -r --experimental ss:///kitchen-photos
--   npx supabase storage rm -r --experimental ss:///avatars
--
-- ## Irreversible
--
-- This project has no backups (Free plan). There is nothing to restore from.

begin;

-- Everything a cook or buyer created. CASCADE resolves the order rather than
-- me hand-maintaining a dependency list that a later migration would silently
-- invalidate.
truncate table
  claim_items,
  claims,
  messages,
  conversations,
  menu_items,
  serving_sessions,
  kitchen_locations,
  kitchens,
  permit_checks,
  device_tokens,
  cooks
cascade;

-- Accounts last. Cascades through auth's own tables (identities, sessions,
-- refresh tokens), which is why this cannot run before the public-schema rows
-- that reference these ids.
delete from auth.users;

commit;

-- Read the result back. Every count here must be 0 except the two reference
-- tables, which must be exactly 4 and 382.
select 'auth.users' as table_name, count(*) as rows from auth.users
union all select 'cooks', count(*) from cooks
union all select 'kitchens', count(*) from kitchens
union all select 'menu_items', count(*) from menu_items
union all select 'serving_sessions', count(*) from serving_sessions
union all select 'conversations', count(*) from conversations
union all select 'messages', count(*) from messages
union all select 'storage.objects (emptied via API, not here)', count(*) from storage.objects
union all select 'permit_checks', count(*) from permit_checks
union all select 'device_tokens', count(*) from device_tokens
union all select 'PRESERVED enforcement_agencies', count(*) from enforcement_agencies
union all select 'PRESERVED permit_registry', count(*) from permit_registry
order by 1;
