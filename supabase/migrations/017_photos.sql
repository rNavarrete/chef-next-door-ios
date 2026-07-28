-- 017 — photos
--
-- The app is photo-first by design (`DESIGN_BRIEF.md` §4) and had nowhere to
-- put a photo. Adds a URL to menu items and cooks, and surfaces the headline
-- dish's photo on discovery rows so the feed, map, search and saved all render
-- from one field.
--
-- Production intent is cook-submitted phone photos in Supabase Storage —
-- `photo_url` is deliberately a plain text URL rather than a storage key so
-- both work. Stock-looking food photography measured as a *distrust* signal in
-- this market (`RESEARCH.md` Finding 6), so the seeded placeholders are test
-- scaffolding, never a template for real listings.

set search_path = public, extensions;

alter table menu_items add column photo_url text;
alter table cooks      add column avatar_url text;

drop function if exists cooks_by_ids(uuid[], double precision, double precision);
drop function if exists search_cooks(text, double precision, double precision, integer, boolean);
drop function if exists cooking_now(double precision, double precision, integer, boolean);
drop type if exists discovery_row;

create type discovery_row as (
  cook_id           uuid,
  display_name      text,
  avatar_url        text,
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
  headline_photo    text,
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
  ),
  -- One pass over the menu instead of six correlated subqueries. With a dozen
  -- cooks the old shape was fine; it would not have stayed fine.
  menu as (
    select mi.cook_id,
           count(*)::int as item_count,
           array_agg(coalesce(mi.name_es, mi.name_en) order by mi.amount_cents) as items,
           (array_agg(mi.photo_url order by mi.amount_cents)
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

create or replace function cooks_by_ids(
  ids uuid[],
  lat double precision,
  lon double precision
)
returns setof discovery_row
language sql stable
set search_path = public, extensions as $$
  select r.* from cooking_now(lat, lon, 1000000, true) r
   where r.cook_id = any(ids);
$$;

grant execute on function cooking_now(double precision, double precision, integer, boolean) to anon, authenticated;
grant execute on function search_cooks(text, double precision, double precision, integer, boolean) to anon, authenticated;
grant execute on function cooks_by_ids(uuid[], double precision, double precision) to anon, authenticated;
