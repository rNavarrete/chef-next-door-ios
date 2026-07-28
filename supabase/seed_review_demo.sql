-- A single demo kitchen, for App Review.
--
--     npx supabase db query --linked --file supabase/seed_review_demo.sql
--
-- ## Why this exists
--
-- Production is empty by design. A reviewer opening Lit Kitchen sees "No
-- kitchens are lit right now", which reads as an incomplete app under
-- Guideline 2.1 — the most common rejection there is. A marketplace with no
-- listings cannot be evaluated: there is nothing to tap, no dish page, no
-- conversation to start.
--
-- So: one kitchen, lit, with a menu. Enough for a reviewer to walk the whole
-- buyer flow, and enough that the app is visibly working.
--
-- ## Deliberately honest about what it is
--
-- The cook is named "Demo Kitchen (Chef Next Door)" rather than dressed up as a
-- real neighbour. A real buyer who stumbles across it before the first genuine
-- cook signs up should be able to tell immediately what they are looking at.
-- Inventing "Maria's Tamales" would populate the feed more convincingly and
-- would be a small lie told to real users.
--
-- It claims no permit. `permit_stage` is effectively "I'll sort this out
-- later": no number is submitted, so the kitchen carries no badge and the
-- county register is never consulted on its behalf. Seeding a fake verified
-- permit would put a trust signal on a kitchen that has not earned one, which
-- is the single thing in this app that must never be faked.
--
-- ## Remove it after approval
--
--     delete from auth.users where email = 'demo@litkitchen.app';
--
-- That cascades the cook, kitchen, menu and session. Do it once real cooks are
-- on the platform — this is scaffolding, not content.

set search_path = public, extensions;

do $$
declare
  v_user uuid;
  v_kitchen uuid;
begin
  -- Idempotent: re-running replaces rather than duplicating.
  delete from auth.users where email = 'demo@litkitchen.app';

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    raw_app_meta_data, raw_user_meta_data, is_anonymous
  ) values (
    '00000000-0000-0000-0000-000000000000', gen_random_uuid(),
    'authenticated', 'authenticated', 'demo@litkitchen.app',
    crypt('DEMO_PASSWORD', gen_salt('bf')),
    now(), now(), now(), '', '', '', '',
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, false
  ) returning id into v_user;

  -- GoTrue refuses a password login for a user with no identity row.
  insert into auth.identities (
    provider_id, user_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) values (
    v_user::text, v_user,
    jsonb_build_object('sub', v_user::text, 'email', 'demo@litkitchen.app',
                       'email_verified', true),
    'email', now(), now(), now()
  );

  -- Registered through the real RPC rather than by hand, so the kitchen gets a
  -- correctly fuzzed public point and the right enforcement agency — the same
  -- rows a genuine signup produces.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_user::text)::text, true);

  select register_cook(
    p_display_name  => 'Demo Kitchen (Chef Next Door)',
    p_contact_method=> 'sms',
    p_contact_value => '(626) 555-0142',
    p_street        => '1148 N Puente Ave',
    p_city          => 'Covina',
    p_postal_code   => '91722',
    p_latitude      => 34.0900,
    p_longitude     => -117.8903,
    p_neighborhood  => 'Covina',
    p_permit_kind   => null,
    p_permit_number => null
  ) into v_kitchen;

  insert into menu_items
    (cook_id, name_en, name_es, category, category_type, description,
     amount_cents, unit, min_quantity, allergens, is_available, sort_order)
  values
    (v_user, 'Pork tamale', 'Tamal de puerco', 'tamales', 'mehko_meal',
     'Pork shoulder, chile colorado, masa de maíz.',
     300, 'each', 3, array['Pork','Corn'], true, 0),
    (v_user, 'Chicken tamale', 'Tamal de pollo', 'tamales', 'mehko_meal',
     'Chicken in salsa verde.',
     300, 'each', 3, array['Corn'], true, 1),
    (v_user, 'Champurrado', 'Champurrado', 'drinks', 'mehko_meal',
     'Masa, chocolate, canela. Served hot.',
     400, 'each', 1, array['Corn','Dairy'], true, 2);

  -- Lit, so the feed has something in it. open_kitchen takes the kitchen,
  -- not just a note — it checks that the caller owns it before opening.
  perform open_kitchen(v_kitchen, null);

  raise notice 'demo cook % with kitchen %', v_user, v_kitchen;
end $$;

select c.display_name,
       (select count(*) from menu_items m where m.cook_id = c.id) as dishes,
       (select count(*) from serving_sessions s
         where s.cook_id = c.id and s.closed_at is null) as open_sessions,
       c.permit_status
  from cooks c
  join auth.users u on u.id = c.id
 where u.email = 'demo@litkitchen.app';
