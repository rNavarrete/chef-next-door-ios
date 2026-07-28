-- 038 — repair the dev fixtures in place
--
-- Two defects in seeded data that `seed_dev_large.sql` now creates correctly,
-- but which the already-seeded database still carries. Re-running the seed
-- would create a second set of cooks rather than fix the first, so the repair
-- has to happen here.
--
-- **Guarded to fixture rows only** (`street like '% Seed St'`), so this is a
-- no-op anywhere that has no fixtures — including production.
--
-- 1. Every kitchen was given ZIP 91722 regardless of city, so a Glendora
--    address carried Covina's ZIP. Wrong on its own terms, and it weakens the
--    ZIP corroboration `verify_permit` (030) leans on.
--
-- 2. Photos came from loremflickr with a single loose keyword. Flickr tagging
--    is broad enough that "tamales" returned a child at a fountain and
--    "portrait" returned a cupcake. Requiring a second keyword (`,food`,
--    `,face`) narrows it to something recognisable. Placeholder imagery is
--    still test scaffolding and never a template for real listings — stock
--    food photography measured as a *distrust* signal in this market
--    (`RESEARCH.md` Finding 6).

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- 1. ZIPs that match the city.
-- ---------------------------------------------------------------------------
update kitchen_locations kl
   set postal_code = case upper(trim(k.city))
         when 'IRWINDALE'    then '91706'
         when 'WEST COVINA'  then '91791'
         when 'AZUSA'        then '91702'
         when 'GLENDORA'     then '91740'
         when 'WALNUT'       then '91789'
         when 'BALDWIN PARK' then '91706'
         when 'COVINA'       then '91722'
         else kl.postal_code
       end
  from kitchens k
 where k.id = kl.kitchen_id
   and kl.street like '% Seed St'
   and kl.postal_code is distinct from (case upper(trim(k.city))
         when 'IRWINDALE'    then '91706'
         when 'WEST COVINA'  then '91791'
         when 'AZUSA'        then '91702'
         when 'GLENDORA'     then '91740'
         when 'WALNUT'       then '91789'
         when 'BALDWIN PARK' then '91706'
         when 'COVINA'       then '91722'
         else kl.postal_code
       end);

-- ---------------------------------------------------------------------------
-- 2. Photo keywords that return food.
-- ---------------------------------------------------------------------------
update menu_items mi
   set photo_url = regexp_replace(mi.photo_url, '\?lock=', ',food?lock=')
  from kitchens k
  join kitchen_locations kl on kl.kitchen_id = k.id
 where k.cook_id = mi.cook_id
   and kl.street like '% Seed St'
   and mi.photo_url like 'https://loremflickr.com/%'
   and mi.photo_url not like '%,food%';

update cooks c
   set avatar_url = regexp_replace(c.avatar_url, '/portrait\?lock=', '/portrait,face?lock=')
  from kitchens k
  join kitchen_locations kl on kl.kitchen_id = k.id
 where k.cook_id = c.id
   and kl.street like '% Seed St'
   and c.avatar_url like '%/portrait?lock=%';
