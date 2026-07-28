-- 024 — photo storage
--
-- 017 added `photo_url` / `avatar_url` as plain text and left production
-- uploads for later. This is later: a bucket cooks can write to, and only
-- inside their own folder.
--
-- **The bucket is public-read on purpose.** These photos appear on the
-- discovery feed to anonymous browsers who have no session and no claim, so a
-- signed URL would have to be minted per row per request for people we cannot
-- identify. Nothing sensitive lives here — a photo of food, chosen by the cook
-- to advertise it. This is the opposite of `kitchen_locations`, and the
-- distinction is deliberate: publish what is meant to be seen, and make what
-- isn't structurally unreachable.

set search_path = public, extensions;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'kitchen-photos', 'kitchen-photos', true,
  5 * 1024 * 1024,                       -- phone photos, downscaled client-side
  array['image/jpeg', 'image/png', 'image/heic', 'image/webp']
)
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Writes are confined to `<uid>/…`. Without the prefix check any signed-in
-- user could overwrite another cook's photos, which is a defacement vector on
-- a surface whose whole job is persuading a stranger the food is real.
drop policy if exists "cooks write their own photos"  on storage.objects;
drop policy if exists "cooks update their own photos" on storage.objects;
drop policy if exists "cooks delete their own photos" on storage.objects;
drop policy if exists "photos are publicly readable"  on storage.objects;

create policy "cooks write their own photos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'kitchen-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "cooks update their own photos"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'kitchen-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "cooks delete their own photos"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'kitchen-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Read is open, matching the bucket. Stated as a policy anyway so the intent
-- is visible next to the write rules rather than implied by a boolean column.
create policy "photos are publicly readable"
  on storage.objects for select to anon, authenticated
  using (bucket_id = 'kitchen-photos');

-- ---------------------------------------------------------------------------
-- Avatar, set during onboarding. `register_cook` (023) predates uploads and a
-- cook has no id to name a folder with until it returns, so the photo is
-- attached in a second step rather than folded into registration.
-- ---------------------------------------------------------------------------
create or replace function set_cook_avatar(p_url text)
returns void language sql security definer
set search_path = public, extensions as $$
  update cooks set avatar_url = nullif(trim(p_url), '') where id = auth.uid();
$$;

revoke all on function set_cook_avatar(text) from public, anon;
grant execute on function set_cook_avatar(text) to authenticated;
