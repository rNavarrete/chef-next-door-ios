-- 018 — headline dish should be the cook's lead item, not the cheapest one
--
-- THE BUG, found by seeding a cook with a full menu:
--
--   Priya N. has six curry dishes. `headline_items` was ordered by price
--   ascending, so her card led with "Side of curry" — the cheapest thing on
--   the menu and the least representative. A cook selling a $15 curry plate
--   was advertised by her $4 side.
--
-- Cheapest is right for the *price* ("from $4"), and wrong for the *headline*.
-- They are two different questions and were being answered by one ORDER BY.
--
-- Headline now follows the order the cook entered their dishes: the first
-- thing you add is what you're known for. That is a better proxy than price
-- and needs no new UI. A explicit "signature dish" flag would be better still
-- and is worth considering when the menu builder gets reordering.

set search_path = public, extensions;

-- Must come first: the function body below references this column and is
-- validated at creation time.
alter table menu_items add column if not exists created_at timestamptz not null default now();

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
  ),
  menu as (
    select mi.cook_id,
           count(*)::int as item_count,
           -- headline: the cook's own ordering
           array_agg(coalesce(mi.name_es, mi.name_en) order by mi.created_at, mi.id) as items,
           (array_agg(mi.photo_url order by mi.created_at, mi.id)
              filter (where mi.photo_url is not null))[1] as photo,
           -- price: genuinely the cheapest, so "from $4" stays true
           min(mi.amount_cents) as min_cents,
           (array_agg(mi.unit order by mi.amount_cents))[1] as min_unit,
           (array_agg(mi.min_quantity order by mi.amount_cents))[1] as min_qty
      from menu_items mi
     where mi.is_available
     group by mi.cook_id
  )
  select
    c.id, c.display_name, c.avatar_url, c.permit_status, c.permit_number,
    a.name, k.neighborhood,
    ST_Distance(k.public_point, o.p),
    ST_Y(k.public_point::geometry),
    ST_X(k.public_point::geometry),
    s.id, s.opened_at, s.last_confirmed_at,
    case when s.id is null then null
         else freshness_of(s.last_confirmed_at, s.closed_at) end,
    coalesce(m.item_count, 0), m.items, m.photo,
    m.min_cents, m.min_unit, m.min_qty
  from cooks c
  join kitchens k on k.cook_id = c.id
  join enforcement_agencies a on a.id = k.agency_id
  left join serving_sessions s on s.cook_id = c.id and s.closed_at is null
  left join menu m on m.cook_id = c.id
  cross join origin o
  where ST_DWithin(k.public_point, o.p, radius_m)
    and (include_closed or s.id is not null)
  order by
    case when s.id is null then 3
         else freshness_rank(freshness_of(s.last_confirmed_at, s.closed_at)) end,
    ST_Distance(k.public_point, o.p);
$$;
