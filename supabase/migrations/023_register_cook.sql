-- 023 — cook registration
--
-- Until now a cook could only come into existence via a seed script. This is
-- the real path, and it has to be a single SECURITY DEFINER RPC because every
-- table it touches is deliberately out of a client's reach:
--
--   cooks              — no INSERT grant (011)
--   kitchen_locations  — no grants at all, ever (004)
--   public_point_for   — execute revoked from anon and authenticated (004)
--
-- Doing it client-side would have meant loosening exactly the three things the
-- location-privacy model rests on.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- Which agency enforces at an address.
--
-- Not cosmetic: in LA County, MEHKO is opt-in *per enforcement agency*, and
-- three cities run their own health departments instead of deferring to the
-- county (COUNSEL_QUESTIONS.md Q2). A cook in Pasadena and a cook two miles
-- away in Altadena are under different regimes — one can sell meals, the other
-- cannot. That has to be resolved at onboarding, not discovered later.
--
-- Q2 is still open with counsel. This encodes the reading the data was seeded
-- under; if counsel says jurisdiction follows something other than the mailing
-- city, this function is the one place that changes.
-- ---------------------------------------------------------------------------
create or replace function agency_for_city(p_city text)
returns uuid language plpgsql stable set search_path = public, extensions as $$
declare v_id uuid; v_norm text;
begin
  v_norm := lower(trim(coalesce(p_city, '')));

  select id into v_id from enforcement_agencies
   where (v_norm = 'pasadena'   and name like 'City of Pasadena%')
      or (v_norm = 'long beach' and name like 'City of Long Beach%')
      or (v_norm = 'vernon'     and name like 'City of Vernon%')
   limit 1;

  -- Everywhere else in the county defers to LA County DPH, which *has* opted
  -- into MEHKO.
  if v_id is null then
    select id into v_id from enforcement_agencies
     where county = 'Los Angeles' and name like 'LA County%'
     limit 1;
  end if;

  return v_id;
end $$;

-- Readable before committing to anything, so onboarding can tell a cook what
-- their city actually allows *before* they type an address and a permit number.
create or replace function agency_for_address(p_city text)
returns table (
  id              uuid,
  name            text,
  mehko_opted_in  boolean,
  cottage_food_ok boolean
)
language sql stable set search_path = public, extensions as $$
  select a.id, a.name, a.mehko_opted_in, a.cottage_food_ok
    from enforcement_agencies a
   where a.id = agency_for_city(p_city);
$$;

grant execute on function agency_for_address(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Registration proper.
--
-- Atomic on purpose: a cook with a `cooks` row but no kitchen, or a kitchen
-- with no location, is a broken account that the app has no screen for. The
-- claim RPC (021) learned this the hard way.
-- ---------------------------------------------------------------------------
create or replace function register_cook(
  p_display_name   text,
  p_contact_method contact_method,
  p_contact_value  text,
  p_street         text,
  p_city           text,
  p_postal_code    text,
  p_latitude       double precision,
  p_longitude      double precision,
  p_neighborhood   text default null,
  p_permit_kind    text default null,
  p_permit_number  text default null
) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_user    uuid := auth.uid();
  v_secret  text;
  v_agency  uuid;
  v_kitchen uuid;
  v_point   geography(Point,4326);
  v_permit  text := nullif(trim(coalesce(p_permit_number, '')), '');
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  -- Idempotency guard rather than an upsert: re-registering would mean a second
  -- kitchen, and nothing in the model supports a cook having two.
  if exists (select 1 from cooks where id = v_user) then
    raise exception 'already registered';
  end if;

  if coalesce(trim(p_display_name), '') = '' then
    raise exception 'display name required';
  end if;
  if coalesce(trim(p_contact_value), '') = '' then
    raise exception 'contact required';
  end if;
  if coalesce(trim(p_street), '') = ''
     or coalesce(trim(p_city), '') = ''
     or coalesce(trim(p_postal_code), '') = '' then
    raise exception 'address required';
  end if;
  if p_latitude is null or p_longitude is null
     or p_latitude  not between -90  and 90
     or p_longitude not between -180 and 180 then
    raise exception 'invalid coordinates';
  end if;

  v_agency := agency_for_city(p_city);
  if v_agency is null then
    raise exception 'no enforcement agency for city %', p_city;
  end if;

  select value into v_secret from app_secrets where key = 'geo_secret';
  if v_secret is null then
    raise exception 'geo_secret is not configured; refusing to publish a location';
  end if;

  v_point := st_setsrid(st_makepoint(p_longitude, p_latitude), 4326)::geography;

  insert into cooks (
    id, display_name, contact_method, contact_value,
    permit_kind, permit_number, permit_agency_id, permit_status
  ) values (
    v_user, trim(p_display_name), p_contact_method, trim(p_contact_value),
    nullif(trim(coalesce(p_permit_kind, '')), ''), v_permit, v_agency,
    -- Never 'verified'. A cook typing their own permit number is an assertion
    -- to be checked (M4), not a credential — and the discovery badge reads
    -- `verified` and nothing else. Self-registration must not be able to
    -- produce a badge.
    case when v_permit is null then 'none'::permit_status
         else 'pending'::permit_status end
  );

  -- public_point is computed here rather than left to the trigger, so the
  -- exact point is never briefly resident in a client-readable column. The
  -- trigger on kitchen_locations recomputes the identical value a moment later.
  insert into kitchens (cook_id, public_point, neighborhood, city, agency_id)
  values (
    v_user,
    public_point_for(v_point, v_secret),
    coalesce(nullif(trim(coalesce(p_neighborhood, '')), ''), trim(p_city)),
    trim(p_city),
    v_agency
  )
  returning id into v_kitchen;

  insert into kitchen_locations (kitchen_id, exact_point, street, city, postal_code)
  values (v_kitchen, v_point, trim(p_street), trim(p_city), trim(p_postal_code));

  return v_kitchen;
end $$;

revoke all on function register_cook(
  text, contact_method, text, text, text, text,
  double precision, double precision, text, text, text
) from public, anon;

grant execute on function register_cook(
  text, contact_method, text, text, text, text,
  double precision, double precision, text, text, text
) to authenticated;

comment on function register_cook is
  'Creates cooks + kitchens + kitchen_locations atomically for auth.uid(). '
  'permit_status is never set to verified here — see M4.';
