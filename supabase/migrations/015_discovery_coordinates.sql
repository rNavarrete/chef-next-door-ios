-- 015 — add the fuzzed coordinate to discovery results, for the map
--
-- `discovery_row` returned distance but no position, which is fine for a feed
-- and useless for a map. Adding `public_lat` / `public_lon`.
--
-- ONLY the grid-snapped public point is ever returned. `kitchen_locations`
-- is not joined here and cannot be — no client role holds a grant on it. The
-- map draws the ~400m cell as an explicit halo, so the uncertainty is visible
-- rather than implied: a buyer sees an area, not a house.
--
-- A composite type can't be altered while functions depend on it, so both
-- functions are dropped and recreated. Order matters: search_cooks calls
-- cooking_now, so it goes first.

set search_path = public, extensions;

drop function if exists search_cooks(text, double precision, double precision, integer, boolean);
drop function if exists cooking_now(double precision, double precision, integer, boolean);
drop type if exists discovery_row;

create type discovery_row as (
  cook_id           uuid,
  display_name      text,
  permit_status     permit_status,
  permit_number     text,
  agency_name       text,
  neighborhood      text,
  distance_m        double precision,
  public_lat        double precision,
  public_lon        double precision,
  session_id        uuid,
  opened_at         timestamptz,
  last_confirmed_at timestamptz,
  freshness         freshness_tier,
  item_count        integer,
  headline_items    text[],
  min_price_cents   integer,
  min_price_unit    price_unit,
  min_price_min_qty integer
);

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
    ST_Y(k.public_point::geometry),   -- fuzzed only
    ST_X(k.public_point::geometry),
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

create or replace function search_cooks(
  q              text,
  lat            double precision,
  lon            double precision,
  radius_m       integer default 8000,
  include_closed boolean default true
)
returns setof discovery_row
language sql stable
set search_path = public, extensions as $$
  with expansion as (select expand_query(q) as terms),
  matched as (
    select distinct mi.cook_id
      from menu_items mi, expansion e
     where mi.is_available
       and (
         mi.search_doc @@ plainto_tsquery('english', immutable_unaccent(q))
         or mi.search_doc @@ plainto_tsquery('spanish', immutable_unaccent(q))
         or exists (
           select 1 from unnest(e.terms) t
            where lower(immutable_unaccent(coalesce(mi.name_es,''))) like '%' || t || '%'
               or lower(immutable_unaccent(coalesce(mi.name_en,''))) like '%' || t || '%'
               or lower(immutable_unaccent(mi.category)) like '%' || t || '%'
         )
         or similarity(lower(immutable_unaccent(coalesce(mi.name_es, mi.name_en, ''))),
                       lower(immutable_unaccent(q))) > 0.35
       )
  )
  select r.* from cooking_now(lat, lon, radius_m, include_closed) r
  join matched m on m.cook_id = r.cook_id;
$$;

grant execute on function cooking_now(double precision, double precision, integer, boolean)
  to anon, authenticated;
grant execute on function search_cooks(text, double precision, double precision, integer, boolean)
  to anon, authenticated;
