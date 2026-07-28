-- 001 — extensions and enums
--
-- Enums first, always. A previous draft of the schema used types before
-- creating them; applying migrations in order against an empty database in CI
-- is the test that catches that class of bug.

-- Supabase installs extensions into the `extensions` schema, a stock Postgres
-- install puts them in `public`. Every function below therefore carries
-- `set search_path = public, extensions` so it resolves in both — a schema
-- that doesn't exist is silently ignored in a search_path, so this is portable
-- rather than environment-specific.
--
-- Found the hard way: `hmac(unknown, text, unknown) does not exist` on the
-- first push to Supabase, after the same file applied cleanly to local PostGIS.
set search_path = public, extensions;

create extension if not exists postgis;
create extension if not exists unaccent;
create extension if not exists pg_trgm;
create extension if not exists pgcrypto;   -- hmac() for location fuzzing

-- unaccent() is STABLE, not IMMUTABLE, because the single-argument form looks
-- up the *default* dictionary at call time — and a generated column requires
-- an immutable expression. The two-argument form with an explicit dictionary
-- is genuinely deterministic, so wrapping it is the standard fix.
--
-- Without this, 006's search_doc fails with "generation expression is not
-- immutable" — which is exactly what happened the first time these migrations
-- were run against a real database.
-- The dictionary is resolved through search_path rather than hardcoded to
-- `public.unaccent`, which does not exist on Supabase.
create or replace function immutable_unaccent(text)
returns text
language sql immutable strict parallel safe
set search_path = public, extensions as $$
  select unaccent('unaccent'::regdictionary, $1)
$$;

create type contact_method      as enum ('sms','whatsapp','instagram');
create type permit_status       as enum ('none','pending','verified','rejected','expired');
create type price_unit          as enum ('each','half_dozen','dozen','loaf','jar','tray','weekly_package','per_person');
create type food_category_type  as enum ('mehko_meal','cottage_food');
create type serving_status      as enum ('closed','serving','sold_out');
create type freshness_tier      as enum ('lit','dimming','unconfirmed','out');
create type claim_status        as enum ('pending','confirmed','completed','no_show','cancelled');
