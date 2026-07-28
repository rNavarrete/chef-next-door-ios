-- 067 — carry a cook's rating through discovery
--
-- `cook_rating(p_cook)` already exists and returns a count and an average, but
-- it is one round trip per cook. The feed cannot use it: rendering twenty cards
-- would mean twenty extra calls, and the filter bar needs the number *before*
-- anything is tapped in order to show a count on the chip.
--
-- So the aggregate joins `discovery_row` and comes back with the card.
--
-- ## Two columns, not one
--
-- `rating` alone is not usable. A single five-star review outranks a cook with
-- forty reviews averaging 4.8, and a filter built on that surfaces whoever got
-- lucky rather than whoever is good — which reads as a quality signal while
-- being a recency signal. `rating_count` travels with it so the client can
-- require a floor before treating the average as meaningful.
--
-- Both are null for a cook nobody has reviewed. Null rather than zero on
-- purpose: zero is a rating, and "nobody has said anything yet" is not the same
-- as "people rated this badly". Every new cook starts in the first state and
-- must not be rendered as the second.
--
-- ## Live at zero reviews
--
-- There are none today. This ships anyway so the day a real review lands the
-- feature appears with nothing to backfill — and, deliberately, with no seeded
-- reviews to make it look populated. Invented menus are scaffolding; invented
-- reviews are fabricated accounts of other people's experiences, and a buyer
-- reading one is being lied to about something this app exists to be honest
-- about.

alter type public.discovery_row
  add attribute rating numeric cascade,
  add attribute rating_count integer cascade;

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
  ),
  rated as (
    select r.cook_id,
           round(avg(r.rating)::numeric, 2) as rating,
           count(*)::int as rating_count
      from reviews r
     group by r.cook_id
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
    m.items_es,
    -- Left join, so an unreviewed cook carries nulls rather than zeroes.
    rt.rating, rt.rating_count
  from cooks c
  join kitchens k on k.cook_id = c.id
  join enforcement_agencies a on a.id = k.agency_id
  left join serving_sessions s on s.cook_id = c.id and s.closed_at is null
  left join menu m on m.cook_id = c.id
  left join rated rt on rt.cook_id = c.id
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

-- `select r.*` expands at parse time, so both wrappers still name the old
-- column list and must be replaced to pick up the two new ones.
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
  'Cooks within radius_m, freshest first. Carries both name resolutions per dish
   and, where reviews exist, an average rating with its count. Rating is null —
   not zero — for a cook nobody has reviewed.';
