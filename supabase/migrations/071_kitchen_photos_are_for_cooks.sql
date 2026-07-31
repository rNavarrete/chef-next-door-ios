-- 071 — only cooks may write to the public photo bucket
--
-- The policy was called "cooks write their own photos" and checked one thing:
--
--     (storage.foldername(name))[1] = auth.uid()::text
--
-- which is a check that you are writing to *your own* folder, not that you are
-- a cook. Anyone holding a session — including an anonymous one, which is two
-- HTTP requests away with the anon key from the app binary — could upload to
-- `kitchen-photos`, a **public** bucket, at 5 MB a file with no limit on how
-- many. Verified by doing it; the object was removed afterwards.
--
-- ## What that is worth to somebody
--
-- Not a data leak. Free image hosting on a supabase.co URL belonging to this
-- project, which is a bill, and a place to park anything they like, which is a
-- takedown notice with this project's name on it. The bucket is public, so
-- whatever lands there is served to anyone with the URL forever.
--
-- ## The fix, and its limit
--
-- Being a cook is having a row in `cooks`, and after 070 having that row
-- requires a permanent account. So this one condition now transitively
-- requires: signed in, not anonymous, and actually running a kitchen.
--
-- `avatars` deliberately keeps the looser rule. Every buyer needs a profile
-- picture and most of them will never cook, so "your own folder" is the right
-- test there — and unlike this one, that bucket is private.

set search_path = public, extensions;

drop policy if exists "cooks write their own photos" on storage.objects;

create policy "cooks write their own photos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'kitchen-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and exists (select 1 from cooks c where c.id = auth.uid())
  );
