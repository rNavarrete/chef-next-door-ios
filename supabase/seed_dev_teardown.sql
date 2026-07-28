-- Removes all development seed data.
--
-- Identifies seeds by the '00000000-…' sentinel on kitchens rather than by
-- name, so a real cook called "Rosa M." is never caught by it.
--
-- Order matters: children before parents, and kitchen_locations before
-- kitchens or the FK blocks.

set search_path = public, extensions;

do $$
declare v_cooks uuid[];
begin
  -- Every cook whose kitchen was created by a seed (seeded kitchens are the
  -- only ones inserted with a placeholder public_point of 0,0 before the
  -- trigger rewrites it — so match on the seeded street marker instead).
  select array_agg(distinct k.cook_id) into v_cooks
    from kitchens k
    join kitchen_locations kl on kl.kitchen_id = k.id
   where kl.street like '% Seed St'
      or kl.street in ('1148 N Puente Ave','420 S Glendora Ave','812 N Azusa Ave');

  if v_cooks is null then
    raise notice 'no seed data found';
    return;
  end if;

  delete from address_disclosures where buyer_id = any(v_cooks) or kitchen_id in
    (select id from kitchens where cook_id = any(v_cooks));
  delete from reviews where claim_id in (select id from claims where cook_id = any(v_cooks));
  delete from claim_items where claim_id in (select id from claims where cook_id = any(v_cooks));
  delete from claims where cook_id = any(v_cooks);
  delete from complaints where cook_id = any(v_cooks);
  delete from follows where cook_id = any(v_cooks);
  delete from menu_items where cook_id = any(v_cooks);
  delete from serving_sessions where cook_id = any(v_cooks);
  delete from kitchen_locations where kitchen_id in (select id from kitchens where cook_id = any(v_cooks));
  delete from kitchens where cook_id = any(v_cooks);
  delete from cooks where id = any(v_cooks);
  delete from auth.users where id = any(v_cooks);

  raise notice 'removed % seeded cooks', array_length(v_cooks, 1);
end $$;
