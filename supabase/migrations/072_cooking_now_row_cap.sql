-- Cap what `cooking_now` will hand back in one call.
--
-- The query was unbounded: it returned every kitchen inside the radius, and the
-- map asks for a radius sized to the viewport, clamped at 80km. With ~90 seed
-- cooks that is 70 kB and nobody notices. At ten thousand cooks in Los Angeles
-- it is a multi-megabyte JSON body parsed on the main thread of a phone on
-- cellular, to draw a map that can show maybe forty pins.
--
-- 400 is far past anything renderable and far short of anything expensive. The
-- ordering already does the hard part — lit kitchens first, then nearest — so
-- the rows that survive the cap are exactly the rows a buyer would have looked
-- at anyway.
--
-- No new parameter. Adding one with a default would create a second overload
-- rather than replacing this signature, and PostgREST would then have two
-- candidates to choose between for the same call.

create or replace function public.cooking_now(lat double precision, lon double precision, radius_m integer DEFAULT 8000, include_closed boolean DEFAULT false)
 RETURNS SETOF discovery_row
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
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
    ST_Distance(k.public_point, o.p)
  -- Capped. See the header note.
  limit 400;
$function$;
