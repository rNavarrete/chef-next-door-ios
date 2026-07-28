-- 058 — the cook's story
--
-- `cooks.bio` has existed since 002, has been grantable to the cook since 032,
-- and is decoded into `Cook.swift`. It has never been shown to anyone and there
-- has never been a way to write it. A column, a grant, and a Swift property, all
-- wired to nothing.
--
-- This migration doesn't add a field. It decides what the field is *for*, and
-- puts a bound on it.
--
-- The product asks a buyer to walk to a stranger's house and eat their food.
-- Every other trust signal here is institutional — a permit number, a county
-- register, a decay ladder that proves someone is really there. Those establish
-- that a kitchen is *legitimate*. None of them establish that a cook is a
-- person, and "why I started cooking, my grandmother's recipe, what feeding
-- this neighbourhood means to me" is the only thing on the platform that can.
--
-- So `bio` is long-form: a story, not a tagline. Which means it needs a ceiling,
-- because it is returned by `cooks_by_ids` on every profile load and there is
-- currently nothing stopping a paste of a novel.

set search_path = public, extensions;

do $$ begin
  if not exists (select 1 where exists (
    select 1 from pg_constraint where conname = 'cooks_bio_length'
  )) then
    -- 2000 characters is roughly 350 words — several paragraphs, comfortably
    -- more than anyone writes on a phone, and small enough that shipping it on
    -- every profile load costs nothing. Enforced here rather than only in the
    -- client because the client is not the only thing that can write it.
    alter table cooks add constraint cooks_bio_length
      check (bio is null or char_length(bio) <= 2000);
  end if;
end $$;

comment on column cooks.bio is
  'The cook''s story, long-form — why they cook, family recipes, what feeding '
  'the neighbourhood means to them. Shown on their profile. Capped at 2000 '
  'characters. Not a tagline: `serving_note` is the short per-session line.';

-- No grants. 032 already gives `authenticated` UPDATE on `bio`, restricted to
-- the cook's own row by RLS, and 055 already includes it in the public SELECT
-- list — a story nobody can read would defeat the point.
