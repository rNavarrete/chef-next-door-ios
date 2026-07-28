-- 019 — explicit menu ordering
--
-- 018 tried to use `created_at` as a proxy for "the dish this cook leads with"
-- and it did not work: dishes added in one batch share a timestamp, so the
-- ordering fell through to a random UUID and the headline was still arbitrary.
-- Verified — Priya N.'s card went from "Side of curry" to "Curry sampler",
-- neither of which is the thing she'd put on a sign.
--
-- The real answer is that menu order is a cook's decision, not something to
-- infer. `sort_order` is the first field the menu builder should let them drag.
--
-- Price ordering stays separate and stays cheapest-first, because "from $4" is
-- a different question from "what are you known for".

set search_path = public, extensions;

alter table menu_items add column if not exists sort_order integer not null default 0;

comment on column menu_items.sort_order is
  'Cook-controlled menu order. Drives the headline dish. Lower is earlier. '
  'Distinct from price ordering, which answers a different question.';

create index if not exists menu_items_order_idx on menu_items (cook_id, sort_order);

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
           array_agg(coalesce(mi.name_es, mi.name_en)
                     order by mi.sort_order, mi.created_at, mi.id) as items,
           (array_agg(mi.photo_url order by mi.sort_order, mi.created_at, mi.id)
              filter (where mi.photo_url is not null))[1] as photo,
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

-- Backfill: give existing rows a deterministic order by price, so nothing is
-- arbitrary until a cook reorders it themselves.
with ranked as (
  select id, row_number() over (partition by cook_id order by amount_cents desc) as rn
    from menu_items
)
update menu_items m set sort_order = r.rn from ranked r where r.id = m.id;
