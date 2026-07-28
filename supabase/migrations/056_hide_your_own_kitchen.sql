-- 056 — a cook does not appear in their own search results
--
-- Discovery is for finding someone else's kitchen. A cook browsing the feed saw
-- their own listing sitting in it — "0.0 mi away", a card they cannot usefully
-- act on, and one that pushes a real neighbour further down a short list. In a
-- launch neighbourhood with a handful of open kitchens, that is a meaningful
-- share of the screen spent on the one result the viewer already knows about.
--
-- One predicate covers everything, because `search_cooks` (017) and
-- `cooks_by_ids` (016) both read through `cooking_now` rather than querying
-- `cooks` themselves. Feed, map, search and saved all inherit it.
--
-- ## `is distinct from`, and this time the trap runs the other way
--
-- 052 found `v_cook <> auth.uid()` silently failing *open* for anonymous
-- callers. Here the same operator would fail *closed*: for an anonymous browser
-- `auth.uid()` is NULL, `c.id <> NULL` is NULL, the WHERE clause drops every
-- row, and the entire public feed goes empty. Same operator, opposite symptom,
-- and this one would have been caught in about ten seconds — which is exactly
-- why the 052 version survived so long. A bug that empties the screen gets
-- found; a bug that quietly permits does not.
--
-- The cook's own kitchen remains reachable through the Kitchen tab, which reads
-- it directly rather than through discovery.

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
           -- No FILTER: the headline photo is the headline dish's own (025).
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
    and not cook_is_blocked(c.id)
    and not i_am_blocked_by(c.id)
    -- Yourself. `is distinct from`, not `<>` — see the header.
    and c.id is distinct from auth.uid()
  order by
    case when s.id is null then 3
         else freshness_rank(freshness_of(s.last_confirmed_at, s.closed_at)) end,
    ST_Distance(k.public_point, o.p);
$$;

grant execute on function cooking_now(double precision, double precision, integer, boolean) to anon, authenticated;
