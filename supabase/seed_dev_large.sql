-- Large development seed — NOT for production.
--
-- 15 cooks across the San Gabriel Valley. Deliberately covers the states that
-- break layouts rather than the ones that flatter them:
--
--   * every freshness tier: lit, dimming (4–6h), unconfirmed (6h+), closed
--   * long Spanish dish names next to two-word English ones
--   * every price unit, including the non-comparable ones (tray, per_person)
--   * a cook with one dish and a cook with six
--   * an unverified cook (permit pending) and one with no permit at all
--   * a cook with no photos at all, to prove the placeholder still works
--   * two cooks in the same ~400m fuzz cell, to test pin overlap
--
-- Photos are keyword-matched placeholders from loremflickr, locked per dish so
-- they're stable across runs. Stock food photography is a *distrust* signal in
-- this market (RESEARCH.md Finding 6) — these exist to exercise layout and
-- image loading, and must never become the template for a real listing.
--
-- Teardown: supabase/seed_dev_teardown.sql

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
do $$
declare
  v_agency  uuid;
  v_cook    uuid;
  v_kitchen uuid;
  r         record;
begin
  select id into v_agency from enforcement_agencies where name like 'LA County%' limit 1;

  for r in
    select * from (values
      -- name, lat, lon, neighborhood, permit, hours_since_open (null = closed),
      -- n_items, cuisine, permit_no, zip
      --
      -- permit_no values are REAL record IDs from LA County's published MEHKO
      -- register, chosen to match each cook's city so verify_permit() actually
      -- passes. They belong to real businesses — this is public record, and
      -- fine for a dev fixture, but do not put this data anywhere public.
      --
      -- Cooks in Covina (only one permit in the whole register), Irwindale
      -- (none) and the deliberately-unpermitted ones carry `null` and stay
      -- unverified. That is a more honest feed than the old all-'verified'
      -- seed, which used fabricated numbers that could never match anything.
      ('Rosa M.',        34.0912, -117.8890, 'Covina',        'pending' , 0.5,  3, 'pizza', null, '91722'),
      ('Doña Chuy',      34.0885, -117.8921, 'Covina',        'pending' , 1.5,  4, 'tamales', null, '91722'),
      ('Kim & Sons',     34.0940, -117.8830, 'Covina',        'pending' , 3.0,  2, 'dumplings', null, '91722'),
      ('Ana P.',         34.0790, -117.8700, 'Covina',        'pending' , 4.5,  3, 'cookies', null, '91722'),
      ('Marisol T.',     34.1010, -117.9050, 'Irwindale',     'pending' , 5.5,  2, 'cupcake', null, '91706'),
      ('Beto R.',        34.0686, -117.9380, 'West Covina',   'verified', 9.0,  1, 'birria', 'PR0366776', '91791'),
      ('Chef Danny',     34.0660, -117.9100, 'West Covina',   'verified', 11.0, 5, 'burger', 'PR0314854', '91791'),
      ('Lupita S.',      34.1336, -117.9076, 'Azusa',         'verified', null, 2, 'bread', 'PR0314583', '91702'),
      ('The Bagel Guy',  34.1290, -117.9200, 'Azusa',         'verified', 2.0,  2, 'bagel', 'PR0326273', '91702'),
      ('Fatima H.',      34.1150, -117.8600, 'Glendora',      'verified', 0.2,  3, 'baklava', 'PR0314581', '91740'),
      ('Nana Ruth',      34.1180, -117.8550, 'Glendora',      'pending',  1.0,  2, 'pie', null, '91740'),
      ('Tito V.',        34.0500, -117.8800, 'Walnut',        'verified', null, 4, 'empanada', 'PR0327553', '91789'),
      ('Sam O.',         34.0480, -117.8760, 'Walnut',        'none',     6.5,  1, 'donut', null, '91789'),
      ('Yolanda C.',     34.0913, -117.8892, 'Covina',        'verified', 0.8,  2, 'churros', 'PR0369129', '91722'),
      ('Priya N.',       34.0820, -117.9300, 'Baldwin Park',  'verified', 7.5,  6, 'curry', 'PR0326027', '91706')
    ) as t(name, lat, lon, hood, permit, hrs, n_items, cuisine, permit_no, zip)
  loop
    v_cook := gen_random_uuid();
    v_kitchen := gen_random_uuid();

    -- id only, so the same file runs against the local stub and the real
    -- Supabase auth schema. Everything else on auth.users is nullable or
    -- defaulted there.
    insert into auth.users (id) values (v_cook) on conflict (id) do nothing;

    insert into cooks (id, display_name, contact_value, phone_verified, permit_status,
                       permit_number, permit_agency_id, avatar_url)
    values (v_cook, r.name, '+15625550100', true, r.permit::permit_status,
            r.permit_no,
            v_agency,
            'https://loremflickr.com/120/120/portrait,face?lock=' || (abs(hashtext(r.name)) % 900));

    insert into kitchens (id, cook_id, public_point, neighborhood, city, agency_id)
    values (v_kitchen, v_cook, ST_SetSRID(ST_MakePoint(0,0),4326)::geography,
            r.hood, r.hood, v_agency);

    -- Real address drives the fuzzed public_point through the trigger, so the
    -- privacy path is exercised rather than bypassed.
    insert into kitchen_locations (kitchen_id, exact_point, street, city, postal_code)
    values (v_kitchen, ST_SetSRID(ST_MakePoint(r.lon, r.lat),4326),
            -- ZIP matches the city. It was hardcoded to 91722 for every cook,
            -- so a Glendora kitchen carried Covina's ZIP — wrong on its own
            -- terms, and it defeats the ZIP corroboration in verify_permit().
            (100 + (random()*900)::int)::text || ' Seed St', r.hood, r.zip);

    -- Menu. Dish names come from a per-cuisine list so search has real
    -- bilingual material to chew on.
    insert into menu_items (cook_id, name_en, name_es, description, category, category_type,
                            allergens, amount_cents, unit, min_quantity, photo_url, is_available,
                            sort_order)
    select v_cook,
           d.name_en, d.name_es, d.descr, r.cuisine,
           d.cat::food_category_type, d.allergens,
           d.cents, d.unit::price_unit, d.min_qty,
           -- Two keywords, not one: Flickr's tagging is loose enough that a
           -- single term like "tamales" returned a child at a fountain.
           'https://loremflickr.com/400/400/' || d.kw || ',food?lock=' || d.lock,
           -- one dish per cook is sold out, to exercise the dimmed row
           (d.idx <> 2),
           -- the cook's own menu order: dish 1 is what they lead with
           d.idx
    from (
      select * from (values
        (1,'Cheese pizza',        'Pizza de queso',        'Wood-fired, thin crust',                    'mehko_meal','{Gluten,Dairy}'::text[], 1400,'each',      1,'pizza',    11),
        (2,'Pepperoni pizza',     null,                    null,                                        'mehko_meal','{Gluten,Dairy,Pork}'::text[], 1600,'each', 1,'pizza',    12),
        (3,'Garlic knots',        null,                    'Six to an order',                           'mehko_meal','{Gluten,Dairy}'::text[],  600,'half_dozen',1,'bread',    13),
        (4,'Party tray',          'Bandeja para fiesta',   'Feeds about ten',                           'mehko_meal','{Gluten,Dairy}'::text[], 8500,'tray',      1,'pizza',    14),
        (5,'Sicilian slice',      null,                    null,                                        'mehko_meal','{Gluten,Dairy}'::text[],  500,'each',      2,'pizza',    15),
        (6,'Calzone',             null,                    null,                                        'mehko_meal','{Gluten,Dairy}'::text[], 1100,'each',      1,'pizza',    16)
      ) as p(idx,name_en,name_es,descr,cat,allergens,cents,unit,min_qty,kw,lock)
      where r.cuisine = 'pizza'
      union all
      select * from (values
        (1,'Pork tamale',         'Tamal de puerco en rojo','Pork shoulder, chile colorado, masa de maíz','mehko_meal','{Pork,Corn}'::text[],   300,'each',      3,'tamales',  21),
        (2,null,                  'Tamal de rajas con queso',null,                                       'mehko_meal','{Dairy,Corn}'::text[], 3600,'dozen',     1,'tamales',  22),
        (3,'Sweet tamale',        'Tamal de elote',         null,                                        'mehko_meal','{Corn,Dairy}'::text[],  300,'each',      3,'tamales',  23),
        (4,'Champurrado',         null,                     null,                                        'mehko_meal','{Dairy}'::text[],       400,'each',      1,'drink',    24),
        (5,null,                  'Tamal de dulce',         null,                                        'mehko_meal','{Corn}'::text[],        300,'each',      3,'tamales',  25),
        (6,'Menudo',              null,                     'Sundays only',                              'mehko_meal','{}'::text[],           1200,'each',      1,'soup',     26)
      ) as t2(idx,name_en,name_es,descr,cat,allergens,cents,unit,min_qty,kw,lock)
      where r.cuisine = 'tamales'
      union all
      select * from (values
        (1,'Chocolate chip cookie',null,                   'Brown butter, sea salt',                     'cottage_food','{Gluten,Dairy,Egg}'::text[], 300,'each', 4,'cookies',  31),
        (2,'Snickerdoodle',       null,                    null,                                         'cottage_food','{Gluten,Dairy,Egg}'::text[], 300,'each', 4,'cookies',  32),
        (3,'Cookie box',          null,                    'A dozen, mixed',                             'cottage_food','{Gluten,Dairy,Egg,Nuts}'::text[], 3200,'dozen',1,'cookies',33),
        (4,'Shortbread',          null,                    null,                                         'cottage_food','{Gluten,Dairy}'::text[],     250,'each', 6,'cookies',  34),
        (5,'Brownie',             null,                    null,                                         'cottage_food','{Gluten,Dairy,Egg}'::text[], 350,'each', 2,'brownie',  35),
        (6,'Blondie',             null,                    null,                                         'cottage_food','{Gluten,Dairy,Egg}'::text[], 350,'each', 2,'brownie',  36)
      ) as t3(idx,name_en,name_es,descr,cat,allergens,cents,unit,min_qty,kw,lock)
      where r.cuisine = 'cookies'
      union all
      -- generic fallback for every other cuisine
      select * from (values
        (1, initcap(r.cuisine),   null, null, 'mehko_meal','{}'::text[],  900,'each', 1, r.cuisine, 41),
        (2, initcap(r.cuisine) || ' plate', null, 'The big one', 'mehko_meal','{}'::text[], 1500,'each', 1, r.cuisine, 42),
        (3, initcap(r.cuisine) || ' box', null, null, 'mehko_meal','{}'::text[], 3000,'half_dozen', 1, r.cuisine, 43),
        (4, initcap(r.cuisine) || ' for a group', null, 'Per person', 'mehko_meal','{}'::text[], 1300,'per_person', 4, r.cuisine, 44),
        (5, initcap(r.cuisine) || ' sampler', null, null, 'mehko_meal','{}'::text[], 2200,'tray', 1, r.cuisine, 45),
        (6, 'Side of ' || r.cuisine, null, null, 'mehko_meal','{}'::text[], 400,'each', 1, r.cuisine, 46)
      ) as t4(idx,name_en,name_es,descr,cat,allergens,cents,unit,min_qty,kw,lock)
      where r.cuisine not in ('pizza','tamales','cookies')
    ) d
    where d.idx <= r.n_items;

    -- One cook deliberately has no photos at all, to prove the placeholder
    -- survives contact with reality.
    if r.name = 'Sam O.' then
      update menu_items set photo_url = null where cook_id = v_cook;
      update cooks set avatar_url = null where id = v_cook;
    end if;

    if r.hrs is not null then
      insert into serving_sessions (cook_id, kitchen_id, opened_at, last_confirmed_at)
      values (v_cook, v_kitchen,
              now() - (r.hrs || ' hours')::interval,
              now() - (r.hrs || ' hours')::interval);
      update cooks set serving_status = 'serving',
             serving_note = case when r.cuisine = 'tamales'
                                 then 'Hice 8 docenas hoy — til 6pm or sold out' else null end
       where id = v_cook;
    end if;
  end loop;
end $$;
