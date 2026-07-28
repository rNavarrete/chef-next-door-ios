-- 066 — keep the seeded kitchens lit while people are testing
--
-- `close_quiet_kitchens()` closes any session untouched for ten hours, which is
-- right and is the point of the freshness ladder. It also means seeded kitchens
-- go dark overnight: eighty-six of ninety closed themselves, and a tester
-- opening the build the next morning finds an almost-empty app and reports it
-- as broken.
--
-- This confirms the fictional kitchens every four hours so the sweep never
-- catches them, and does nothing else.
--
-- ## Scope, which is the whole safety argument
--
-- Matched on `seed.%@litkitchen.test` and the single demo account. A real
-- cook's session is never touched. Relighting a real kitchen would be the app
-- asserting somebody is cooking when they have not said so — a buyer drives
-- over on the strength of it — and that is precisely the lie the decay ladder
-- exists to prevent. The function is deliberately incapable of it rather than
-- merely unlikely to: the WHERE clause is the guard, and there is no parameter
-- that could widen it.
--
-- ## Remove this before launch
--
--     select cron.unschedule('seed-keep-lit');
--     drop function if exists relight_seed_kitchens();
--
-- It is scaffolding for a test cohort, and it should not outlive one. There is
-- a teardown for the seed data itself in seed_test_kitchens_teardown.sql; this
-- is the other half.

set search_path = public, extensions;

create or replace function relight_seed_kitchens()
returns integer
language plpgsql security definer
set search_path = public, extensions as $$
declare v_count integer;
begin
  -- Reopen any that closed.
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

  -- Confirm the open ones so the next sweep passes over them.
  update serving_sessions s
     set last_confirmed_at = now() - (random() * interval '20 minutes')
    from auth.users u
   where u.id = s.cook_id
     and s.closed_at is null
     and (u.email like 'seed.%@litkitchen.test' or u.email = 'demo@litkitchen.app');
  get diagnostics v_count = row_count;

  update cooks c
     set serving_status = 'serving'
    from auth.users u
   where u.id = c.id
     and (u.email like 'seed.%@litkitchen.test' or u.email = 'demo@litkitchen.app');

  return v_count;
end $$;

revoke all on function relight_seed_kitchens() from public, anon, authenticated;

comment on function relight_seed_kitchens is
  'Keeps the seeded and demo kitchens lit for testing. Scoped to '
  'seed.%@litkitchen.test and demo@litkitchen.app; never touches a real cook. '
  'Remove before launch — see migration 066.';

-- Every four hours, comfortably inside the ten-hour quiet window.
select cron.unschedule('seed-keep-lit')
 where exists (select 1 from cron.job where jobname = 'seed-keep-lit');

select cron.schedule('seed-keep-lit', '7 */4 * * *',
                     'select public.relight_seed_kitchens()');
