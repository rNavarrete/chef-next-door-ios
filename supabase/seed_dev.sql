-- Development seed — NOT a migration, and not for production.
--
-- Three cooks around the Covina launch cluster, with the dish names and price
-- shapes taken from real listings in RESEARCH.md. Includes one cook in the
-- `unconfirmed` state (lit 9 hours ago, silent since), because that is the
-- case most likely to be built wrong from being easy to forget.
--
-- Remove with supabase/seed_dev_teardown.sql.

set search_path = public, extensions;

insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
values
  ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-000000000000','authenticated','authenticated','seed.maria@example.test', now(), now()),
  ('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-000000000000','authenticated','authenticated','seed.beto@example.test', now(), now()),
  ('33333333-3333-3333-3333-333333333333','00000000-0000-0000-0000-000000000000','authenticated','authenticated','seed.yesenia@example.test', now(), now())
on conflict (id) do nothing;

insert into cooks (id, display_name, contact_value, phone_verified, permit_status, permit_number, permit_agency_id)
select v.id, v.name, '+15625550100', true, 'verified'::permit_status, v.permit,
       (select id from enforcement_agencies where name like 'LA County%' limit 1)
from (values
  ('11111111-1111-1111-1111-111111111111'::uuid,'María G.','24417'),
  ('22222222-2222-2222-2222-222222222222'::uuid,'Beto R.','24418'),
  ('33333333-3333-3333-3333-333333333333'::uuid,'Yesenia O.','24419')
) as v(id,name,permit)
on conflict (id) do nothing;

insert into kitchens (id, cook_id, public_point, neighborhood, city, agency_id)
select v.kid, v.cid, ST_SetSRID(ST_MakePoint(0,0),4326)::geography, v.hood, v.city,
       (select id from enforcement_agencies where name like 'LA County%' limit 1)
from (values
  ('aaaaaaaa-0000-0000-0000-000000000001'::uuid,'11111111-1111-1111-1111-111111111111'::uuid,'Covina','Covina'),
  ('aaaaaaaa-0000-0000-0000-000000000002'::uuid,'22222222-2222-2222-2222-222222222222'::uuid,'West Covina','West Covina'),
  ('aaaaaaaa-0000-0000-0000-000000000003'::uuid,'33333333-3333-3333-3333-333333333333'::uuid,'Azusa','Azusa')
) as v(kid,cid,hood,city)
on conflict (id) do nothing;

-- The trigger derives each public_point from these, so the fuzzing path is
-- exercised rather than bypassed.
insert into kitchen_locations (kitchen_id, exact_point, street, city, postal_code) values
  ('aaaaaaaa-0000-0000-0000-000000000001', ST_SetSRID(ST_MakePoint(-117.8903,34.0900),4326),'1148 N Puente Ave','Covina','91722'),
  ('aaaaaaaa-0000-0000-0000-000000000002', ST_SetSRID(ST_MakePoint(-117.9380,34.0686),4326),'420 S Glendora Ave','West Covina','91790'),
  ('aaaaaaaa-0000-0000-0000-000000000003', ST_SetSRID(ST_MakePoint(-117.9076,34.1336),4326),'812 N Azusa Ave','Azusa','91702')
on conflict (kitchen_id) do nothing;

insert into menu_items (cook_id, name_en, name_es, description, category, category_type, allergens, amount_cents, unit, min_quantity) values
  ('11111111-1111-1111-1111-111111111111','Pork tamale','Tamal de puerco en rojo','Pork shoulder, chile colorado, masa de maíz','tamales','mehko_meal','{Pork,Corn}',300,'each',3),
  ('11111111-1111-1111-1111-111111111111',null,'Tamal de rajas con queso',null,'tamales','mehko_meal','{Dairy,Corn}',3600,'dozen',1),
  ('11111111-1111-1111-1111-111111111111','Champurrado',null,null,'champurrado','mehko_meal','{Dairy}',400,'each',1),
  ('22222222-2222-2222-2222-222222222222','Beef birria','Birria de res',null,'birria','mehko_meal','{Beef}',400,'each',1),
  ('33333333-3333-3333-3333-333333333333','Sourdough loaf','Masa madre',null,'sourdough','cottage_food','{Gluten}',900,'loaf',1);

-- María: lit and freshly confirmed. Beto: lit 9h ago, silent since →
-- `unconfirmed`, and must rank below her. Yesenia: closed.
insert into serving_sessions (cook_id, kitchen_id, opened_at, last_confirmed_at) values
  ('11111111-1111-1111-1111-111111111111','aaaaaaaa-0000-0000-0000-000000000001', now() - interval '2 hours', now() - interval '20 minutes'),
  ('22222222-2222-2222-2222-222222222222','aaaaaaaa-0000-0000-0000-000000000002', now() - interval '9 hours', now() - interval '9 hours')
on conflict do nothing;

update cooks set serving_status = 'serving',
       serving_note = 'Hice 8 docenas hoy — til 6pm or sold out'
 where id = '11111111-1111-1111-1111-111111111111';
update cooks set serving_status = 'serving' where id = '22222222-2222-2222-2222-222222222222';
