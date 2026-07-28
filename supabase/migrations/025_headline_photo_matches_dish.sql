-- 025 — the headline photo must be the headline dish's photo
--
-- 017 chose `headline_photo` as the first **non-null** photo in the menu, and
-- 019 kept that when it switched ordering to `sort_order`. The name, meanwhile,
-- is simply the first item. Those are different dishes whenever the headline
-- dish has no photo.
--
-- It never showed while photos were seed-only, because the seed gave every
-- dish one. The moment cooks could upload (024), a real kitchen listed
-- "Pozole rojo" over a photo of the agua de limón — the buyer's read is that
-- this is what the pozole looks like, which is worse than showing nothing.
--
-- So: same dish or no photo. A placeholder is honest; a photo of a different
-- dish is not.

set search_path = public, extensions;

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
           -- No FILTER: index [1] is the headline dish's own photo, null
           -- included. Ordering is identical to `items`, so the photo and the
           -- name can never describe different dishes.
           (array_agg(mi.photo_url
                      order by mi.sort_order, mi.created_at, mi.id))[1] as photo,
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

grant execute on function cooking_now(double precision, double precision, integer, boolean) to anon, authenticated;
