-- Carry both dish names through discovery, so the feed and the dish page agree.
--
-- `cooking_now` built its card names with `coalesce(mi.name_es, mi.name_en)` —
-- Spanish first, always, regardless of who is reading. The client picks by
-- locale (`MenuItem.displayName`: Spanish reader gets `name_es ?? name_en`,
-- everyone else gets `name_en ?? name_es`). So an English reader saw one name
-- on the feed card and a different one the moment they opened the dish:
-- "Stuffed poblano" in the list, "Chile relleno" on the page. Same dish, two
-- names, one screen apart.
--
-- This is the defect 044 fixed for order lines, alive again on discovery. The
-- fix is the same: the server has no business choosing a language. It sends
-- both resolutions and the client picks the one matching its locale.
--
--   headline_items      → coalesce(name_en, name_es)   English reader
--   headline_items_es   → coalesce(name_es, name_en)   Spanish reader
--
-- Both are non-null and identically ordered, so they index in parallel. The
-- coalesce (rather than the raw column) mirrors `displayName`'s fallback
-- exactly, and keeps NULLs out of a `text[]` the client decodes as [String].
--
-- Only `cooking_now` aggregates the array. `search_cooks` and `cooks_by_ids`
-- are `select r.*` wrappers over it — but `*` is expanded at parse time, so
-- their stored trees still name 20 columns and would fail with a return-type
-- mismatch. They are replaced verbatim to re-expand against the wider type.

alter type public.discovery_row
  add attribute headline_items_es text[] cascade;

create or replace function public.cooking_now(
  lat double precision,
  lon double precision,
  radius_m integer default 8000,
  include_closed boolean default false
) returns setof discovery_row
language sql stable
set search_path to 'public', 'extensions'
as $$
  with origin as (
    select ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography as p
  ),
  menu as (
    select mi.cook_id,
           count(*)::int as item_count,
           -- Two resolutions of the same list, same order, both non-null.
           array_agg(coalesce(mi.name_en, mi.name_es)
                     order by mi.sort_order, mi.created_at, mi.id) as items,
           array_agg(coalesce(mi.name_es, mi.name_en)
                     order by mi.sort_order, mi.created_at, mi.id) as items_es,
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
    m.min_cents, m.min_unit, m.min_qty,
    m.items_es
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

create or replace function public.search_cooks(
  q text,
  lat double precision,
  lon double precision,
  radius_m integer default 8000,
  include_closed boolean default true
) returns setof discovery_row
language sql stable
set search_path to 'public', 'extensions'
as $$
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

create or replace function public.cooks_by_ids(
  ids uuid[],
  lat double precision,
  lon double precision
) returns setof discovery_row
language sql stable
set search_path to 'public', 'extensions'
as $$
  select r.* from cooking_now(lat, lon, 1000000, true) r
   where r.cook_id = any(ids);
$$;

comment on function public.cooking_now(double precision, double precision, integer, boolean) is
  'Cooks within radius_m, freshest first. Returns both name resolutions per dish
   (headline_items English-preferred, headline_items_es Spanish-preferred) so the
   client picks by locale rather than the server choosing for everyone.';
