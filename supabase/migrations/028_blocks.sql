-- 028 — blocking a kitchen
--
-- Reporting and blocking are different acts and the app should not conflate
-- them. A report is a message to us (and, for food safety, onward to the
-- enforcement agency). A block is a private preference: "stop showing me this
-- kitchen." Most people who want the second do not want the first, and forcing
-- them through a complaint form to get it means we learn nothing and they get
-- nothing.
--
-- Blocks are one-directional and invisible to the cook. There is no notice, no
-- count, and nothing on the cook's side that changes — a cook who could tell
-- they had been blocked could work out by whom, in a market where the buyer
-- lives a few streets away.

set search_path = public, extensions;

create table if not exists blocked_cooks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  cook_id    uuid not null references cooks(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, cook_id)
);

alter table blocked_cooks enable row level security;

-- Only ever your own rows, for every operation. In particular there is no
-- policy letting a cook read rows about themselves.
drop policy if exists blocks_own on blocked_cooks;
create policy blocks_own on blocked_cooks for all
  using (blocker_id = auth.uid())
  with check (blocker_id = auth.uid());

grant select, insert, delete on blocked_cooks to authenticated;

-- ---------------------------------------------------------------------------
-- Discovery honours the block.
--
-- Filtered here rather than client-side so it holds for the feed, the map,
-- search and saved at once — `search_cooks` and `cooks_by_ids` both read
-- through this function.
--
-- **Via a SECURITY DEFINER helper, not an inline subquery.** `cooking_now` is a
-- plain function, so anything it reads is read as the *caller* — and `anon` has
-- no grant on `blocked_cooks`. An inline `not exists (select ... from
-- blocked_cooks ...)` therefore fails with "permission denied for table
-- blocked_cooks" for every anonymous browser, taking the whole feed with it.
-- Granting the table to `anon` would work but widens the surface for no reason;
-- this returns a boolean about the caller's own blocks and nothing else.
-- ---------------------------------------------------------------------------
create or replace function cook_is_blocked(p_cook uuid)
returns boolean language sql stable security definer
set search_path = public, extensions as $$
  select exists (
    select 1 from blocked_cooks
     where blocker_id = auth.uid() and cook_id = p_cook
  );
$$;

grant execute on function cook_is_blocked(uuid) to anon, authenticated;

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
  order by
    case when s.id is null then 3
         else freshness_rank(freshness_of(s.last_confirmed_at, s.closed_at)) end,
    ST_Distance(k.public_point, o.p);
$$;

grant execute on function cooking_now(double precision, double precision, integer, boolean) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Reporting.
--
-- `complaints` has existed since 008 with nothing writing to it. The one thing
-- worth encoding here rather than in the UI: a food-safety complaint is the
-- enforcement agency's business, not ours, and the app must hand back the
-- agency that actually covers that kitchen (they differ by city — see
-- `agency_for_city`, 023). We are not the regulator and must not look like one.
-- ---------------------------------------------------------------------------
create or replace function report_cook(
  p_cook  uuid,
  p_kind  text,
  p_body  text default null,
  p_claim uuid default null
)
returns table (agency_name text, is_food_safety boolean)
language plpgsql security definer
set search_path = public, extensions as $$
declare v_agency text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if p_kind not in ('food_safety', 'hygiene', 'listing', 'other') then
    raise exception 'unknown complaint kind %', p_kind;
  end if;
  if not exists (select 1 from cooks where id = p_cook) then
    raise exception 'no such cook';
  end if;

  insert into complaints (cook_id, claim_id, reporter_id, kind, body)
  values (p_cook, p_claim, auth.uid(), p_kind, nullif(trim(coalesce(p_body, '')), ''));

  select a.name into v_agency
    from kitchens k join enforcement_agencies a on a.id = k.agency_id
   where k.cook_id = p_cook
   limit 1;

  return query select v_agency, p_kind in ('food_safety', 'hygiene');
end $$;

revoke all on function report_cook(uuid, text, text, uuid) from public, anon;
grant execute on function report_cook(uuid, text, text, uuid) to authenticated;
