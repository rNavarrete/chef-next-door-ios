-- Removes everything seed_test_kitchens.sql and seed_test_menus.sql created.
--
--     npx supabase db query --linked --file supabase/seed_test_kitchens_teardown.sql
--
-- Run this before real cooks are on the platform. Thirty-five fictional
-- kitchens are useful for testing and dishonest in a live marketplace, and the
-- longer they sit the more likely somebody messages one.
--
-- Scoped by email pattern rather than by a date or a hand-kept list, so it
-- cannot take a real account with it: every seeded user is
-- seed.<slug>@litkitchen.test and nothing else uses that domain. The demo
-- kitchen from seed_review_demo.sql is deliberately NOT matched — it is
-- demo@litkitchen.app and has its own teardown line.
--
-- Cooks, kitchens, menu items, serving sessions, conversations and follows all
-- cascade from auth.users. Photos are not touched: every seeded dish points at
-- the shared seed/seedpix images, which are meant to outlive any one seeding.

set search_path = public, extensions;

-- opened_by_user is NO ACTION (063) and would block the delete.
update serving_sessions set opened_by_user = null
 where opened_by_user in (
   select id from auth.users where email like 'seed.%@litkitchen.test');

delete from auth.users where email like 'seed.%@litkitchen.test';

select
  (select count(*) from auth.users where email like 'seed.%@litkitchen.test') as seeded_users_left,
  (select count(*) from cooks) as cooks_remaining,
  (select count(*) from menu_items) as dishes_remaining,
  (select count(*) from enforcement_agencies) as PRESERVED_agencies,
  (select count(*) from permit_registry) as PRESERVED_registry;
