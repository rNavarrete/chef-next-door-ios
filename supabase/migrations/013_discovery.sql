-- 013 — buyer discovery: open-now feed, bilingual search
--
-- Two RPCs, both returning the same row shape so the feed and search results
-- render through one component.
--
-- Everything here computes distance from `kitchens.public_point` and never
-- from `kitchen_locations.exact_point`. That is not a convenience — ordering
-- by true distance leaks the exact location through result *ordering* even
-- though the coordinate is never returned (SPIKE_LOCATION_PRIVACY.md).

set search_path = public, extensions;

create type discovery_row as (
  cook_id           uuid,
  display_name      text,
  permit_status     permit_status,
  permit_number     text,
  agency_name       text,
  neighborhood      text,
  distance_m        double precision,
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

-- Enums have no ordinal cast, so ranking gets an explicit, readable order
-- rather than depending on declaration order. Defined before its first use.
create or replace function freshness_rank(t freshness_tier)
returns integer language sql immutable as $$
  select case t when 'lit' then 0 when 'dimming' then 1
                when 'unconfirmed' then 2 else 3 end;
$$;

-- ---------------------------------------------------------------------------
-- Who's cooking near me right now.
--
-- Ordering is freshness first, then distance. `unconfirmed` (6h+ since the
-- cook last asserted service) must never outrank a confirmed kitchen and is
-- never the first row of the feed — PRD §5, rule 3.
-- ---------------------------------------------------------------------------
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
    c.id,
    c.display_name,
    c.permit_status,
    c.permit_number,
    a.name,
    k.neighborhood,
    ST_Distance(k.public_point, o.p),
    s.id,
    s.opened_at,
    s.last_confirmed_at,
    freshness_of(s.last_confirmed_at, s.closed_at),
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

-- ---------------------------------------------------------------------------
-- Bilingual search.
--
-- The research finding this exists for: titles mix Spanish and English
-- mid-string, so we cannot pick a language per query (RESEARCH.md Finding 4).
-- No language toggle — instead the query expands through a curated synonym
-- table, and the expansion is RETURNED so the UI can show buyers *why* a
-- result matched ("también: tamales · tamalito · pork tamale").
-- ---------------------------------------------------------------------------
create or replace function expand_query(q text)
returns text[]
language sql stable
set search_path = public, extensions as $$
  with normalized as (
    select lower(immutable_unaccent(trim(q))) as term
  ),
  -- direct hits, plus anything sharing a canonical form with them
  canonicals as (
    select distinct ds.canonical
      from dish_synonyms ds, normalized n
     where lower(immutable_unaccent(ds.term)) = n.term
        or lower(immutable_unaccent(ds.canonical)) = n.term
        -- typo tolerance: "biria" → "birria", observed in real listings
        or similarity(lower(immutable_unaccent(ds.term)), n.term) > 0.5
  )
  select coalesce(
    array_agg(distinct ds.term order by ds.term),
    array[]::text[]
  )
  from dish_synonyms ds
  join canonicals c on c.canonical = ds.canonical;
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
         -- full-text in both language configs
         mi.search_doc @@ plainto_tsquery('english', immutable_unaccent(q))
         or mi.search_doc @@ plainto_tsquery('spanish', immutable_unaccent(q))
         -- or any expanded synonym appears in either name
         or exists (
           select 1 from unnest(e.terms) t
            where lower(immutable_unaccent(coalesce(mi.name_es,''))) like '%' || t || '%'
               or lower(immutable_unaccent(coalesce(mi.name_en,''))) like '%' || t || '%'
               or lower(immutable_unaccent(mi.category)) like '%' || t || '%'
         )
         -- or the dish name is a near-miss for the raw query
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
grant execute on function expand_query(text) to anon, authenticated;
grant execute on function freshness_rank(freshness_tier) to anon, authenticated;
