-- 060 — the cook's own cover photo
--
-- The profile hero currently renders `headline_photo` — the same image as the
-- feed card the buyer just tapped. A quarter of the destination screen spent
-- confirming the tap rather than saying anything new.
--
-- This gives a cook one photo that is about the *kitchen* rather than a single
-- dish: the setup mid-service, the spread on the counter, hands working, the
-- pot. It is the closest thing to flair this product should offer.
--
-- ## Deliberately a photo, not a logo
--
-- The obvious version of "let cooks brand their page" is a logo slot. We are
-- not building one. `DESIGN_BRIEF.md` §Imagery:
--
--   > Do **not** art-direct toward stock-food-photography polish — our research
--   > found stock-looking photos are a *distrust* signal in this market.
--
-- A logo is further along that road than a stock photo: it is the strongest
-- available "this is a business" signal, in a product whose entire wedge is
-- that this is a neighbour with a county permit number. Most home cooks have no
-- logo, and the ones who make one will read as *less* trustworthy beside a cook
-- who photographed a foil tray on their own counter.
--
-- So: a public URL to a photo the cook took, in the same bucket as their dish
-- photos, uploaded through the same path. Nothing here can hold a wordmark that
-- the dish photos could not already hold.

set search_path = public, extensions;

alter table cooks add column if not exists cover_url text;

comment on column cooks.cover_url is
  'Public URL of the cook''s kitchen cover photo. Falls back to the headline '
  'dish photo when null. A photo, not a logo — see migration 060.';

-- ---------------------------------------------------------------------------
-- Grants, matching the two migrations that own each side.
-- ---------------------------------------------------------------------------

-- Read: 055 revoked blanket SELECT and re-granted only the public columns. A
-- cover nobody can see would defeat the point.
grant select (cover_url) on cooks to anon, authenticated;

-- Write: 032 revoked blanket UPDATE and re-granted the columns a cook owns.
-- This is one of them — RLS still restricts it to their own row.
grant update (cover_url) on cooks to authenticated;

-- ---------------------------------------------------------------------------
-- Setting it.
--
-- Mirrors `set_cook_avatar` (031) rather than letting the client PATCH the
-- column: the grant above would permit a direct write, but going through a
-- function keeps every cook-photo write on one auditable path and gives us
-- somewhere to put validation when it is needed.
-- ---------------------------------------------------------------------------
create or replace function set_kitchen_cover(p_url text)
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not authenticated'; end if;

  -- Empty clears it, so a cook can go back to their headline dish. Storing ''
  -- would render as a broken image rather than as "no cover".
  update cooks
     set cover_url = nullif(trim(coalesce(p_url, '')), '')
   where id = v_me;

  if not found then raise exception 'not a cook'; end if;
end $$;

revoke all on function set_kitchen_cover(text) from public, anon;
grant execute on function set_kitchen_cover(text) to authenticated;
