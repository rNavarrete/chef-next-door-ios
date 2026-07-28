-- Development cook logins — NOT for production.
--
-- The seeded cooks were created as bare `auth.users` rows (id only) so the
-- seed would run against both the local stub and real Supabase. That's fine
-- for foreign keys and useless for signing in.
--
-- This gives each seeded cook an email + password so the cook-side surfaces
-- can actually be used. Writing to auth.users directly is a dev-seeding
-- shortcut; real cooks sign up through the app.
--
--   email:    <firstname>@seed.test   e.g. yolanda@seed.test
--   password: litkitchen
--
-- Everything here is gated on the seeded-address marker, so it can never
-- touch a real account. Remove with seed_dev_teardown.sql.

set search_path = public, extensions;

do $$
declare r record; v_email text;
begin
  for r in
    select c.id, c.display_name
      from cooks c
      join kitchens k on k.cook_id = c.id
      join kitchen_locations kl on kl.kitchen_id = k.id
     where kl.street like '% Seed St'
        or kl.street in ('1148 N Puente Ave','420 S Glendora Ave','812 N Azusa Ave')
  loop
    v_email := lower(
      regexp_replace(split_part(r.display_name, ' ', 1), '[^a-zA-Z]', '', 'g')
    ) || '@seed.test';

    update auth.users
       set email               = v_email,
           encrypted_password  = crypt('litkitchen', gen_salt('bf')),
           email_confirmed_at  = coalesce(email_confirmed_at, now()),
           aud                 = 'authenticated',
           role                = 'authenticated',
           instance_id         = coalesce(instance_id, '00000000-0000-0000-0000-000000000000'),
           raw_app_meta_data   = '{"provider":"email","providers":["email"]}'::jsonb,
           raw_user_meta_data  = coalesce(raw_user_meta_data, '{}'::jsonb),
           created_at          = coalesce(created_at, now()),
           updated_at          = now(),
           -- GoTrue scans these into non-nullable Go strings. A manually
           -- inserted auth.users row leaves them NULL, and every sign-in then
           -- fails with a 500 "Database error querying schema" that says
           -- nothing about the actual cause. Empty string, not NULL.
           confirmation_token         = coalesce(confirmation_token, ''),
           recovery_token             = coalesce(recovery_token, ''),
           email_change               = coalesce(email_change, ''),
           email_change_token_new     = coalesce(email_change_token_new, ''),
           email_change_token_current = coalesce(email_change_token_current, ''),
           phone_change               = coalesce(phone_change, ''),
           phone_change_token         = coalesce(phone_change_token, ''),
           reauthentication_token     = coalesce(reauthentication_token, '')
     where id = r.id;

    -- GoTrue also expects an identity row for the email provider; without it
    -- the user exists but cannot authenticate.
    insert into auth.identities (
      id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
    )
    values (
      gen_random_uuid(), r.id, r.id::text,
      jsonb_build_object('sub', r.id::text, 'email', v_email, 'email_verified', true),
      'email', now(), now(), now()
    )
    on conflict do nothing;
  end loop;
end $$;

select display_name, u.email
  from cooks c join auth.users u on u.id = c.id
 where u.email like '%@seed.test'
 order by display_name;
