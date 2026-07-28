-- Keep the seeded kitchens lit.
--
--     npx supabase db query --linked --file supabase/seed_relight.sql
--
-- ## Why this is needed
--
-- `close_quiet_kitchens()` runs hourly and closes any session whose
-- `last_confirmed_at` is more than ten hours old. That is correct behaviour and
-- exactly what the app is for — a kitchen nobody has touched since this morning
-- is probably not still cooking.
--
-- It also means seeded kitchens go dark about ten hours after seeding. Eighty-six
-- of ninety closed themselves overnight, and a tester opening the build the next
-- morning would find an almost-empty app and reasonably report it as broken.
--
-- Re-seeding fixes it but is a sledgehammer: it deletes and recreates every cook,
-- which churns their ids and would orphan any conversation a tester had started.
-- This only touches the session rows.
--
-- ## Scope
--
-- Matched on `seed.%@litkitchen.test` and nothing else. A real cook's kitchen is
-- never relit — that would be the app lying about somebody, asserting they are
-- cooking when they have not said so, which is the single thing the freshness
-- ladder exists to prevent.
--
-- The demo kitchen (demo@litkitchen.app) is included: App Review needs it lit,
-- and it is equally fictional.

set search_path = public, extensions;

-- Reopen anything that has closed itself.
insert into serving_sessions (cook_id, kitchen_id, opened_at, last_confirmed_at, status)
select c.id, k.id,
       now() - (random() * interval '4 hours'),
       now() - (random() * interval '20 minutes'),
       'serving'
  from cooks c
  join kitchens k on k.cook_id = c.id
  join auth.users u on u.id = c.id
 where (u.email like 'seed.%@litkitchen.test' or u.email = 'demo@litkitchen.app')
   and not exists (
     select 1 from serving_sessions s
      where s.cook_id = c.id and s.closed_at is null
   );

-- And push the ones still open forward, so the next sweep does not catch them.
update serving_sessions s
   set last_confirmed_at = now() - (random() * interval '20 minutes')
  from auth.users u
 where u.id = s.cook_id
   and s.closed_at is null
   and (u.email like 'seed.%@litkitchen.test' or u.email = 'demo@litkitchen.app');

update cooks c
   set serving_status = 'serving'
  from auth.users u
 where u.id = c.id
   and (u.email like 'seed.%@litkitchen.test' or u.email = 'demo@litkitchen.app');

select count(*) filter (where s.closed_at is null) as lit_now,
       count(distinct s.cook_id) as kitchens
  from serving_sessions s
  join auth.users u on u.id = s.cook_id
 where (u.email like 'seed.%@litkitchen.test' or u.email = 'demo@litkitchen.app')
   and s.closed_at is null;
