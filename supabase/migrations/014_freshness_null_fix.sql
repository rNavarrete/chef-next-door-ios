-- 014 — freshness_of(NULL) returned 'unconfirmed' instead of 'out'
--
-- THE BUG, and why it matters more than it looks:
--
--   select case
--     when closed is not null then 'out'
--     when now() - last_confirmed < interval '4 hours' then 'lit'
--     ...
--     else 'unconfirmed'
--   end
--
-- For a cook with no open session, `last_confirmed` is NULL. `now() - NULL`
-- is NULL, `NULL < interval` is NULL — not true — so every branch falls
-- through to the `else`, and a kitchen that is definitively **closed** was
-- reported as `unconfirmed`.
--
-- That is the wrong direction to fail. `unconfirmed` means "lit a while ago,
-- might still be cooking, go ask" — it keeps the kitchen in the feed and
-- offers the buyer a way to check. A closed cook would have appeared as
-- possibly-cooking, which is precisely the false-positive the decay ladder
-- exists to prevent (PRD §5).
--
-- Found by seeding a closed cook and reading the feed. Invisible in the unit
-- tests because the Swift `FreshnessTier.of` takes a non-optional Date and so
-- cannot express this case at all — the type system hid it.

set search_path = public, extensions;

create or replace function freshness_of(last_confirmed timestamptz, closed timestamptz)
returns freshness_tier language sql stable as $$
  select case
    when last_confirmed is null                      then 'out'::freshness_tier
    when closed is not null                          then 'out'::freshness_tier
    when now() - last_confirmed < interval '4 hours' then 'lit'
    when now() - last_confirmed < interval '6 hours' then 'dimming'
    else 'unconfirmed'
  end;
$$;

-- Belt and braces: cooking_now already left-joins the session, so make the
-- no-session case explicit rather than relying on the function's NULL
-- handling. A closed cook reports no freshness at all.
create or replace function cooking_now(
  lat            double precision,
  lon            double precision,
  radius_m       integer default 8000,
  include_closed boolean default false
)
returns setof discovery_row
language sql stable
set search_path = public, extensions as $$
  with origin as (
    select ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography as p
  )
  select
    c.id, c.display_name, c.permit_status, c.permit_number,
    a.name, k.neighborhood,
    ST_Distance(k.public_point, o.p),
    s.id, s.opened_at, s.last_confirmed_at,
    case when s.id is null then null
         else freshness_of(s.last_confirmed_at, s.closed_at) end,
    (select count(*)::int from menu_items mi
      where mi.cook_id = c.id and mi.is_available),
    (select array_agg(coalesce(mi.name_es, mi.name_en) order by mi.amount_cents)
       from menu_items mi where mi.cook_id = c.id and mi.is_available),
    (select min(mi.amount_cents) from menu_items mi
      where mi.cook_id = c.id and mi.is_available),
    (select mi.unit from menu_items mi
      where mi.cook_id = c.id and mi.is_available
      order by mi.amount_cents limit 1),
    (select mi.min_quantity from menu_items mi
      where mi.cook_id = c.id and mi.is_available
      order by mi.amount_cents limit 1)
  from cooks c
  join kitchens k on k.cook_id = c.id
  join enforcement_agencies a on a.id = k.agency_id
  left join serving_sessions s on s.cook_id = c.id and s.closed_at is null
  cross join origin o
  where ST_DWithin(k.public_point, o.p, radius_m)
    and (include_closed or s.id is not null)
  order by
    case when s.id is null then 3
         else freshness_rank(freshness_of(s.last_confirmed_at, s.closed_at)) end,
    ST_Distance(k.public_point, o.p);
$$;
