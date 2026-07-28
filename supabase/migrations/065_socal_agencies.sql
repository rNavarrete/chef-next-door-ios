-- 065 — enforcement agencies beyond Los Angeles County
--
-- `agency_for_city` special-cased Pasadena, Long Beach and Vernon and sent
-- everything else to LA County DPH. Its own comment says "everywhere else *in
-- the county*", which was true when every kitchen was in the San Gabriel
-- Valley. It stops being true the moment a cook registers in Irvine, and it
-- fails silently: the kitchen is created, attached to the wrong regulator, and
-- nothing anywhere says so.
--
-- That is not cosmetic. `agency_name` reaches buyers in two places:
--
--   CookDetailView — "<agency> · cooked and picked up the same day"
--   ReportSheet    — the agency a buyer is told to contact about a
--                    **food-safety** problem
--
-- A San Diego kitchen currently tells a buyer to report food poisoning to Los
-- Angeles County. That is wrong at the one moment the field has to be right.
--
-- ## mehko_opted_in defaults to FALSE, deliberately
--
-- MEHKO is adopted county by county, and which counties have adopted it changes
-- with board votes. I have not verified the current status for any county
-- below, so every new row says false and carries a note saying so.
--
-- False is the safe direction. It makes the app warn a cook that meals may not
-- be permitted where they live — annoying if wrong. True in error tells a cook
-- that hot food is legal when it is not, which is how somebody ends up cooking
-- illegally on our say-so. The onboarding notice exists precisely because that
-- mistake was once made in the other direction for Pasadena.
--
-- **Verify each county with its health department and flip the flag before
-- accepting cooks there.** Los Angeles stays true; it is the one this app was
-- built against and the one whose register we mirror.

set search_path = public, extensions;

insert into enforcement_agencies (name, county, mehko_opted_in, cottage_food_ok, notes)
values
  ('Orange County Health Care Agency',                    'Orange',         false, true,
   'MEHKO opt-in NOT VERIFIED. Confirm with the county before accepting cooks.'),
  ('County of San Diego Dept. of Environmental Health',   'San Diego',      false, true,
   'MEHKO opt-in NOT VERIFIED. Confirm with the county before accepting cooks.'),
  ('Riverside County Dept. of Environmental Health',      'Riverside',      false, true,
   'MEHKO opt-in NOT VERIFIED. Confirm with the county before accepting cooks.'),
  ('San Bernardino County Environmental Health Services', 'San Bernardino', false, true,
   'MEHKO opt-in NOT VERIFIED. Confirm with the county before accepting cooks.'),
  ('Ventura County Environmental Health Division',        'Ventura',        false, true,
   'MEHKO opt-in NOT VERIFIED. Confirm with the county before accepting cooks.'),
  ('Santa Barbara County Environmental Health Services',  'Santa Barbara',  false, true,
   'MEHKO opt-in NOT VERIFIED. Confirm with the county before accepting cooks.')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- City → agency, as data rather than as a widening CASE expression.
-- ---------------------------------------------------------------------------
create table if not exists agency_cities (
  city      text primary key,
  agency_id uuid not null references enforcement_agencies(id) on delete cascade
);

alter table agency_cities enable row level security;
drop policy if exists agency_cities_read on agency_cities;
create policy agency_cities_read on agency_cities for select using (true);
grant select on agency_cities to anon, authenticated;

comment on table agency_cities is
  'Which regulator covers which city. Lowercase, trimmed. Absent cities fall '
  'back to LA County, which is correct for the launch market and wrong '
  'everywhere else — add rows before opening a new county.';

insert into agency_cities (city, agency_id)
select c.city, a.id
  from (values
    -- Orange
    ('anaheim','Orange'),('irvine','Orange'),('santa ana','Orange'),
    ('huntington beach','Orange'),('costa mesa','Orange'),('fullerton','Orange'),
    ('garden grove','Orange'),('orange','Orange'),('tustin','Orange'),
    ('san clemente','Orange'),('laguna beach','Orange'),('buena park','Orange'),
    -- San Diego
    ('san diego','San Diego'),('chula vista','San Diego'),('oceanside','San Diego'),
    ('escondido','San Diego'),('carlsbad','San Diego'),('el cajon','San Diego'),
    ('vista','San Diego'),('encinitas','San Diego'),('la mesa','San Diego'),
    -- Riverside
    ('riverside','Riverside'),('moreno valley','Riverside'),('corona','Riverside'),
    ('temecula','Riverside'),('murrieta','Riverside'),('palm springs','Riverside'),
    ('hemet','Riverside'),('indio','Riverside'),('menifee','Riverside'),
    -- San Bernardino
    ('san bernardino','San Bernardino'),('fontana','San Bernardino'),
    ('ontario','San Bernardino'),('rancho cucamonga','San Bernardino'),
    ('victorville','San Bernardino'),('chino','San Bernardino'),
    ('redlands','San Bernardino'),('upland','San Bernardino'),
    -- Ventura
    ('oxnard','Ventura'),('thousand oaks','Ventura'),('ventura','Ventura'),
    ('simi valley','Ventura'),('camarillo','Ventura'),
    -- Santa Barbara
    ('santa barbara','Santa Barbara'),('santa maria','Santa Barbara'),('goleta','Santa Barbara')
  ) as c(city, county)
  join enforcement_agencies a on a.county = c.county
on conflict (city) do nothing;

-- ---------------------------------------------------------------------------
-- The lookup, now consulting that table first.
-- ---------------------------------------------------------------------------
create or replace function agency_for_city(p_city text)
returns uuid
language plpgsql stable
set search_path to 'public', 'extensions'
as $$
declare v_id uuid; v_norm text;
begin
  v_norm := lower(trim(coalesce(p_city, '')));

  -- City health departments inside LA County, which are not the county's.
  select id into v_id from enforcement_agencies
   where (v_norm = 'pasadena'   and name like 'City of Pasadena%')
      or (v_norm = 'long beach' and name like 'City of Long Beach%')
      or (v_norm = 'vernon'     and name like 'City of Vernon%')
   limit 1;

  -- Then the city→county map.
  if v_id is null then
    select agency_id into v_id from agency_cities where city = v_norm;
  end if;

  -- Unknown cities still fall back to LA County. That is right for the launch
  -- market and wrong outside it, which is why the table above exists and why
  -- adding rows is part of opening a new county — not an afterthought.
  if v_id is null then
    select id into v_id from enforcement_agencies
     where county = 'Los Angeles' and name like 'LA County%'
     limit 1;
  end if;

  return v_id;
end $$;
