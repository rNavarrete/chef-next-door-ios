-- Light up kitchens for testing.
--
-- Not a migration. Development data only.
--
--     npx supabase db query --linked --file supabase/seed_light_kitchens.sql
--
-- ## Why this keeps being needed
--
-- Migration 054 closes any session that has gone ten hours without a
-- confirmation, and the decay ladder (007) demotes a session to `dimming` after
-- three hours and `unconfirmed` after six. Both are correct and neither should
-- be relaxed for convenience: a kitchen that stays lit forever is exactly the
-- stale-availability failure the whole ladder exists to prevent.
--
-- The consequence is that a seeded feed goes quiet overnight, which is fine for
-- production and inconvenient for looking at the app. Hence this.
--
-- ## Every kitchen, not the first eight
--
-- This lit eight and stopped, which was right when the seed was a handful of
-- cooks in one valley. With ~92 spread from San Diego to Santa Maria, eight
-- lights up a scatter nobody is standing next to: a tester in Long Beach could
-- open a feed that had just been "refreshed" and still see almost nothing,
-- because the eight lit kitchens were all in the San Gabriel Valley.
--
-- Density is the point of a seed. A thin one is indistinguishable from a broken
-- app, and that is the exact confusion this was creating.
--
-- ## Confirmed, not just opened
--
-- Setting `opened_at` alone is not enough. `freshness_of()` reads
-- `last_confirmed_at`, so a session opened ten hours ago with no confirmation
-- reads as `unconfirmed` no matter how it was created. Both are stamped to
-- `now()` here, which is what a cook actively serving would produce.
--
-- `opened_by = 'seed'` per migration 053, so `suspicious_sessions()` does not
-- report these as unattributable opens. That function exists to answer "did
-- anyone open a kitchen who shouldn't have" — seeded rows must not be noise in
-- that signal.

set search_path = public, extensions;

do $$
declare
  v_lit int := 0;
  r     record;
begin
  for r in
    select c.id as cook_id, k.id as kitchen_id, c.display_name
      from cooks c
      join kitchens k on k.cook_id = c.id
     -- Only kitchens with something on the menu. A lit card with no dish and no
     -- price renders as a broken listing, which is worse test data than a dark
     -- kitchen.
     where exists (
       select 1 from menu_items mi where mi.cook_id = c.id and mi.is_available
     )
     order by c.display_name
  loop
    -- Idempotent. An already-open session is confirmed rather than duplicated —
    -- `open_kitchen` has the same rule, and a second open row for one cook would
    -- break the partial unique index the activity tokens rely on.
    if exists (
      select 1 from serving_sessions s
       where s.cook_id = r.cook_id and s.closed_at is null
    ) then
      update serving_sessions
         set last_confirmed_at = now()
       where cook_id = r.cook_id and closed_at is null;
    else
      insert into serving_sessions (cook_id, kitchen_id, opened_by, opened_at, last_confirmed_at)
      values (r.cook_id, r.kitchen_id, 'seed', now(), now());
    end if;

    update cooks set serving_status = 'serving' where id = r.cook_id;
    v_lit := v_lit + 1;
  end loop;

  raise notice '% kitchens lit', v_lit;
end $$;

-- What a buyer will now see, by freshness. `freshness_of` is the same function
-- the feed ranks on, so this is the real answer rather than a proxy for it.
select freshness_of(s.last_confirmed_at, s.closed_at) as freshness,
       count(*) as kitchens
  from serving_sessions s
 where s.closed_at is null
 group by 1 order by 1;
