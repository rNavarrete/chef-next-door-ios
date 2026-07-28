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
  v_wanted int := 8;
  v_lit    int := 0;
  r        record;
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
    exit when v_lit >= v_wanted;

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
    raise notice 'lit: %', r.display_name;
  end loop;

  raise notice '% kitchens lit', v_lit;
end $$;

-- What a buyer will now see. `freshness_of` is the same function the feed ranks
-- on, so this is the real answer rather than a proxy for it.
select co.display_name,
       freshness_of(s.last_confirmed_at, s.closed_at) as freshness,
       s.opened_by
  from serving_sessions s
  join cooks co on co.id = s.cook_id
 where s.closed_at is null
 order by co.display_name;
