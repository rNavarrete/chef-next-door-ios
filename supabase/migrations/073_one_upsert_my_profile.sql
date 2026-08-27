-- 073 — there can only be one `upsert_my_profile`
--
-- 041 created `upsert_my_profile(p_name, p_avatar)`. 069 added a third
-- argument for the bio and wrote a new `create or replace` — but a different
-- argument list is a different function, so the two-argument version was never
-- replaced. Both have been live ever since.
--
-- That is invisible until a caller omits the optional arguments. Swift's
-- synthesized `Encodable` uses `encodeIfPresent` for optional properties, so
-- `saveProfile(name:avatarPath:bio:)` with no photo and no bio sends exactly
-- `{"p_name": "..."}`. Both overloads accept a lone `p_name` — the rest have
-- defaults — and PostgREST refuses to guess:
--
--   PGRST203  Could not choose the best candidate function between:
--             public.upsert_my_profile(p_name => text, p_avatar => text),
--             public.upsert_my_profile(p_name => text, p_avatar => text,
--                                      p_bio => text)
--
-- HTTP 300, no row written. In the app that surfaced as "Couldn't save that.
-- Try again in a moment." on the messaging gate's name step — the first thing
-- a new buyer is asked for, and unreachable past it. Anyone with a photo or a
-- bio to send sent enough arguments to disambiguate, which is why this
-- survived: the failure needed the emptiest possible profile, which is
-- precisely what a first-time buyer has.
--
-- Dropping the older one is safe. Every call it can serve, the three-argument
-- version serves identically: `p_bio` defaults to null, and null means "leave
-- the bio alone" by 069's own rule.
--
-- Server-side, so it repairs clients already in the field, including any build
-- sitting in App Review.

set search_path = public, extensions;

drop function if exists upsert_my_profile(text, text);

-- Guard: exactly one overload may exist under this name from here on.
do $$
declare n int;
begin
  select count(*) into n
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'upsert_my_profile';
  if n <> 1 then
    raise exception 'expected exactly 1 upsert_my_profile, found %', n;
  end if;
end $$;
